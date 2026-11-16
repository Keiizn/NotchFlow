import AppKit
import AVFoundation
import LocalAuthentication

/// Déverrouillage du Mac par reconnaissance faciale (webcam, 100 % local).
///
/// macOS n'offre aucune API pour autoriser une ouverture de session : comme les autres
/// outils de ce type, NotchFlow tape le mot de passe enregistré dans l'écran verrouillé
/// quand le visage est reconnu. C'est un confort, pas une sécurité équivalente à Touch ID.
@MainActor
final class FaceUnlockService: ObservableObject {
    static let shared = FaceUnlockService()

    enum Liveness: String, CaseIterable, Identifiable {
        case off, motion, blink
        var id: String { rawValue }
        var title: String {
            switch self {
            case .off: "Désactivée"
            case .motion: "Léger : mouvement de tête"
            case .blink: "Strict : clignement des yeux"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case recognized(String)
        case failed(String)
        case paused(String)
    }

    private enum Mode { case none, unlock, test, enroll }

    // MARK: Réglages

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "face.enabled"); enabledChanged() } }
    @Published var threshold: Double { didSet { defaults.set(threshold, forKey: "face.threshold") } }
    @Published var liveness: Liveness { didSet { defaults.set(liveness.rawValue, forKey: "face.liveness") } }
    @Published var sessionHours: Int { didSet { defaults.set(sessionHours, forKey: "face.sessionHours"); refreshArmState() } }
    @Published var showOnLockScreen: Bool { didSet { defaults.set(showOnLockScreen, forKey: "face.lockScreenIsland") } }
    @Published var scanOnMouse: Bool { didSet { defaults.set(scanOnMouse, forKey: "face.scanOnMouse") } }
    @Published var scanSeconds: Double { didSet { defaults.set(scanSeconds, forKey: "face.scanSeconds") } }
    @Published var requiredFrames: Int { didSet { defaults.set(requiredFrames, forKey: "face.requiredFrames") } }
    @Published var autoRearm: Bool { didSet { defaults.set(autoRearm, forKey: "face.autoRearm") } }

    // MARK: État

    @Published private(set) var identities: [FaceIdentity] = []
    @Published private(set) var hasPassword = false
    @Published private(set) var isLocked = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var armedUntil: Date?
    @Published private(set) var faceVisible = false
    @Published private(set) var livenessPassed = false
    /// Scores en direct (test et écran verrouillé), par visage.
    @Published private(set) var liveScores: [UUID: Float] = [:]
    @Published private(set) var testRunning = false
    @Published private(set) var enrolling = false
    @Published private(set) var enrollProgress: Double = 0
    @Published private(set) var enrollHint = ""
    @Published var lastError: String?

    var isArmed: Bool {
        guard let armedUntil, secret != nil else { return false }
        return armedUntil > Date()
    }

    var cameraAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }

    private let defaults = UserDefaults.standard
    private let camera = FaceCamera()
    private var mode: Mode = .none
    private var secret: Data?
    private var history: [FaceSample] = []
    private var streakIdentity: UUID?
    private var streak = 0
    private var spoofCount = 0
    private var deadline: Task<Void, Never>?
    private var lockedAt = Date.distantPast
    private var lastScanEnd = Date.distantPast
    private var scansThisLock = 0
    private var failedTypings = 0
    private var mouseTimer: Timer?
    private var lastMouse = NSPoint.zero
    private var enrollSamples: [[Float]] = []
    private var lastEnrollTime: TimeInterval = 0
    private var started = false

    private init() {
        defaults.register(defaults: [
            "face.enabled": false,
            "face.threshold": 0.92,
            "face.liveness": Liveness.motion.rawValue,
            "face.sessionHours": 24,
            "face.lockScreenIsland": true,
            "face.scanOnMouse": true,
            "face.scanSeconds": 6.0,
            "face.requiredFrames": 3,
            "face.autoRearm": true,
        ])
        enabled = defaults.bool(forKey: "face.enabled")
        threshold = defaults.double(forKey: "face.threshold")
        liveness = Liveness(rawValue: defaults.string(forKey: "face.liveness") ?? "") ?? .motion
        sessionHours = defaults.integer(forKey: "face.sessionHours")
        showOnLockScreen = defaults.bool(forKey: "face.lockScreenIsland")
        scanOnMouse = defaults.bool(forKey: "face.scanOnMouse")
        scanSeconds = defaults.double(forKey: "face.scanSeconds")
        requiredFrames = defaults.integer(forKey: "face.requiredFrames")
        autoRearm = defaults.bool(forKey: "face.autoRearm")
    }

    // MARK: Démarrage

    func start() {
        guard !started else { return }
        started = true
        hasPassword = FaceVault.hasPassword
        identities = FaceVault.loadIdentities()

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if LockState.isLocked { self?.didLock() }
            }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.didUnlock() }
        }
        distributed.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.trigger() }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    self?.trigger()
                }
            }
        }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stopScan(result: nil) }
            }
        }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshArmState() }
        }

        // Session ouverte à l'instant (lancement à la connexion) : on active avec Touch ID.
        if enabled, hasPassword, autoRearm {
            Task {
                try? await Task.sleep(for: .seconds(3))
                if !LockState.isLocked { await self.arm() }
            }
        }
    }

    private func enabledChanged() {
        if enabled {
            hasPassword = FaceVault.hasPassword
            if identities.isEmpty { identities = FaceVault.loadIdentities() }
        } else {
            disarm()
        }
    }

    // MARK: Session (Touch ID)

    /// Active le déverrouillage pour `sessionHours` heures après Touch ID / mot de passe.
    func arm() async {
        guard hasPassword else {
            lastError = "Enregistre d'abord ton mot de passe de session."
            return
        }
        let context = LAContext()
        context.localizedCancelTitle = "Plus tard"
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "activer le déverrouillage facial de NotchFlow")
            guard ok else { return }
        } catch {
            return
        }
        guard let data = FaceVault.readPassword() else {
            lastError = "Impossible de lire le mot de passe dans le trousseau. Enregistre-le à nouveau."
            return
        }
        secret = data
        armedUntil = Date().addingTimeInterval(TimeInterval(sessionHours) * 3600)
        failedTypings = 0
        lastError = nil
        if case .paused = phase { phase = .idle }
    }

    func disarm() {
        if let count = secret?.count {
            secret?.resetBytes(in: 0..<count)
        }
        secret = nil
        armedUntil = nil
    }

    private func refreshArmState() {
        if let armedUntil, armedUntil <= Date() { disarm() }
        objectWillChange.send()
    }

    // MARK: Mot de passe

    /// Vérifie puis enregistre le mot de passe du compte. Renvoie un message d'erreur.
    func savePassword(_ password: String) async -> String? {
        guard !password.isEmpty else { return "Le mot de passe est vide." }
        let valid = await Task.detached { FaceVault.verifyAccountPassword(password) }.value
        guard valid else { return "Ce n'est pas le mot de passe de ta session macOS." }
        guard FaceVault.storePassword(password) else { return "Impossible d'écrire dans le trousseau." }
        hasPassword = true
        secret = Data(password.utf8)
        armedUntil = Date().addingTimeInterval(TimeInterval(sessionHours) * 3600)
        failedTypings = 0
        if case .paused = phase { phase = .idle }
        return nil
    }

    func deletePassword() {
        FaceVault.deletePassword()
        hasPassword = false
        disarm()
    }

    func eraseEverything() {
        cancelEnroll()
        stopTest()
        FaceVault.eraseAll()
        identities = []
        hasPassword = false
        enabled = false
        disarm()
    }

    // MARK: Visages

    func setEnabled(_ identity: FaceIdentity, _ value: Bool) {
        guard let index = identities.firstIndex(where: { $0.id == identity.id }) else { return }
        identities[index].enabled = value
        FaceVault.save(identities)
    }

    func rename(_ identity: FaceIdentity, to name: String) {
        guard let index = identities.firstIndex(where: { $0.id == identity.id }) else { return }
        identities[index].name = name
        FaceVault.save(identities)
    }

    func delete(_ identity: FaceIdentity) {
        identities.removeAll { $0.id == identity.id }
        FaceVault.save(identities)
    }

    /// Seuil conseillé : le plus strict des profils actifs.
    var suggestedThreshold: Double? {
        let active = identities.filter(\.enabled)
        guard !active.isEmpty else { return nil }
        return active.map(\.suggestedThreshold).max()
    }

    // MARK: Enregistrement d'un visage

    func startEnroll() {
        guard mode == .none || mode == .test else { return }
        stopTest()
        enrollSamples = []
        enrollProgress = 0
        enrollHint = "Regarde la caméra"
        enrolling = true
        mode = .enroll
        startCamera()
    }

    func cancelEnroll() {
        guard mode == .enroll else { return }
        stopCamera()
        mode = .none
        enrolling = false
        enrollSamples = []
    }

    private static let enrollTarget = 24

    var enrollComplete: Bool { enrollSamples.count >= Self.enrollTarget }

    func finishEnroll(name: String) {
        guard enrollComplete else { return }
        let identity = FaceIdentity(name: name.isEmpty ? "Visage \(identities.count + 1)" : name, samples: enrollSamples)
        let first = identities.isEmpty
        identities.append(identity)
        FaceVault.save(identities)
        if first { threshold = identity.suggestedThreshold }
        cancelEnroll()
        enrolling = false
        enrollSamples = []
    }

    private func handleEnroll(_ sample: FaceSample?) {
        guard let sample else {
            enrollHint = "Aucun visage : place-toi face à la caméra"
            return
        }
        if sample.framedByDevice {
            enrollHint = "Photo ou écran détecté"
            return
        }
        guard sample.rect.width >= 0.16 else {
            enrollHint = "Rapproche-toi un peu"
            return
        }
        guard sample.time - lastEnrollTime >= 0.25, !enrollComplete else { return }
        // Garde des prises de vue variées.
        let similar = enrollSamples.contains { FaceMath.cosine($0, sample.embedding) > 0.995 }
        if similar && enrollSamples.count > 4 { return }
        enrollSamples.append(sample.embedding)
        lastEnrollTime = sample.time
        enrollProgress = Double(enrollSamples.count) / Double(Self.enrollTarget)
        switch enrollSamples.count {
        case ..<6: enrollHint = "Regarde droit la caméra"
        case ..<12: enrollHint = "Tourne doucement la tête à gauche et à droite"
        case ..<18: enrollHint = "Lève et baisse légèrement le menton"
        case ..<Self.enrollTarget: enrollHint = "Encore un instant…"
        default:
            enrollHint = "Terminé !"
            stopCamera()
        }
    }

    // MARK: Test (Labo)

    func startTest() {
        guard mode == .none else { return }
        resetScanState()
        mode = .test
        testRunning = true
        phase = .scanning
        startCamera()
        deadline = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self.stopTest()
        }
    }

    func stopTest() {
        guard mode == .test else { return }
        deadline?.cancel()
        stopCamera()
        mode = .none
        testRunning = false
        if case .recognized = phase {} else { phase = .idle }
    }

    // MARK: Verrouillage

    private func didLock() {
        guard !isLocked else { return }
        isLocked = true
        lockedAt = Date()
        scansThisLock = 0
        failedTypings = 0
        stopTest()
        cancelEnroll()
        phase = isArmed || !enabled ? .idle : .paused(pauseReason)
        if enabled, showOnLockScreen { LockScreenOverlay.shared.show() }
        startMouseWatch()
    }

    private func didUnlock() {
        guard isLocked else { return }
        isLocked = false
        stopMouseWatch()
        stopScan(result: nil)
        LockScreenOverlay.shared.hide()
        phase = .idle
        liveScores = [:]
        if enabled, hasPassword, autoRearm, !isArmed {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await self.arm()
            }
        }
    }

    private var pauseReason: String {
        if !hasPassword { return "Mot de passe non enregistré" }
        if !KeyTyper.isAllowed { return "Autorisation Accessibilité requise" }
        if identities.filter(\.enabled).isEmpty { return "Aucun visage enregistré" }
        return "Touch ID requis pour réactiver"
    }

    private func startMouseWatch() {
        lastMouse = NSEvent.mouseLocation
        mouseTimer?.invalidate()
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let location = NSEvent.mouseLocation
                let moved = hypot(location.x - self.lastMouse.x, location.y - self.lastMouse.y) > 4
                self.lastMouse = location
                if moved, self.scanOnMouse { self.trigger() }
            }
        }
    }

    private func stopMouseWatch() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }

    /// Déclenche une analyse (réveil de l'écran, souris, clic sur l'île).
    func trigger(manual: Bool = false) {
        guard enabled, isLocked, mode == .none, LockState.isLocked, LockState.isOnConsole else { return }
        // Laisse le temps de s'éloigner après avoir verrouillé.
        guard manual || Date().timeIntervalSince(lockedAt) > 4 else { return }
        guard manual || Date().timeIntervalSince(lastScanEnd) > 2.5 else { return }
        guard manual || scansThisLock < 6 else { return }
        guard isArmed, KeyTyper.isAllowed, !identities.filter(\.enabled).isEmpty else {
            phase = .paused(pauseReason)
            return
        }
        guard cameraAuthorized else {
            phase = .paused("Accès à la caméra refusé")
            return
        }
        scansThisLock += 1
        resetScanState()
        mode = .unlock
        phase = .scanning
        if showOnLockScreen { LockScreenOverlay.shared.show() }
        startCamera()
        deadline = Task {
            try? await Task.sleep(for: .seconds(self.scanSeconds))
            guard !Task.isCancelled else { return }
            self.stopScan(result: self.faceVisible ? "Visage non reconnu" : "Aucun visage détecté")
        }
    }

    private func stopScan(result: String?) {
        guard mode == .unlock else { return }
        deadline?.cancel()
        stopCamera()
        mode = .none
        lastScanEnd = Date()
        if let result { phase = .failed(result) }
    }

    // MARK: Caméra et analyse

    private func resetScanState() {
        history = []
        streak = 0
        streakIdentity = nil
        spoofCount = 0
        faceVisible = false
        livenessPassed = false
        liveScores = [:]
    }

    private func startCamera() {
        camera.onSample = { [weak self] sample in
            Task { @MainActor in self?.handle(sample) }
        }
        camera.start { [weak self] ok in
            guard !ok else { return }
            Task { @MainActor in
                guard let self else { return }
                self.lastError = "Caméra indisponible (capot fermé ou caméra utilisée ?)"
                if self.mode == .unlock { self.stopScan(result: "Caméra indisponible") }
                if self.mode == .test { self.stopTest() }
            }
        }
    }

    private func stopCamera() {
        camera.onSample = nil
        camera.stop()
    }

    private func handle(_ sample: FaceSample?) {
        switch mode {
        case .none: return
        case .enroll: handleEnroll(sample)
        case .unlock, .test: handleRecognition(sample)
        }
    }

    private func handleRecognition(_ sample: FaceSample?) {
        guard let sample else {
            faceVisible = false
            streak = 0
            return
        }
        faceVisible = true
        history.append(sample)
        history.removeAll { sample.time - $0.time > 2.5 }

        if sample.framedByDevice {
            spoofCount += 1
            if spoofCount >= 2 {
                livenessPassed = false
                if mode == .unlock { stopScan(result: "Photo ou écran détecté") }
                else { phase = .failed("Photo ou écran détecté") }
                return
            }
        }

        var scores: [UUID: Float] = [:]
        var best: (identity: FaceIdentity, centroid: Float, top: Float)?
        for identity in identities where identity.enabled {
            let score = identity.score(sample.embedding)
            scores[identity.id] = score.centroid
            if best == nil || score.centroid > best!.centroid {
                best = (identity, score.centroid, score.top)
            }
        }
        liveScores = scores

        let limit = Float(threshold)
        if let best, best.centroid >= limit, best.top >= limit {
            streak = streakIdentity == best.identity.id ? streak + 1 : 1
            streakIdentity = best.identity.id
        } else {
            streak = 0
            streakIdentity = nil
        }

        livenessPassed = checkLiveness()
        guard streak >= max(1, requiredFrames), livenessPassed,
              let name = best?.identity.name else { return }

        switch mode {
        case .test:
            phase = .recognized(name)
        case .unlock:
            unlock(as: name)
        default:
            break
        }
    }

    private func checkLiveness() -> Bool {
        switch liveness {
        case .off:
            return true
        case .motion:
            guard history.count >= 4 else { return false }
            let noses = history.map(\.noseOffset), yaws = history.map(\.yaw), pitches = history.map(\.pitch)
            let range: ([Double]) -> Double = { ($0.max() ?? 0) - ($0.min() ?? 0) }
            return range(noses) > 0.03 || range(yaws) > 0.05 || range(pitches) > 0.05
        case .blink:
            let values = history.map(\.eyeOpenness)
            guard let open = values.max(), open > 0.12 else { return false }
            // Un œil qui se ferme puis se rouvre.
            guard let closedIndex = values.firstIndex(where: { $0 < open * 0.55 }) else { return false }
            return values[closedIndex...].contains { $0 > open * 0.8 }
                && values[..<closedIndex].contains { $0 > open * 0.8 }
        }
    }

    private func unlock(as name: String) {
        stopScan(result: nil)
        guard LockState.isLocked, LockState.isOnConsole, let secret, isArmed else {
            phase = .paused(pauseReason)
            return
        }
        phase = .recognized(name)
        let data = secret
        Task.detached(priority: .userInitiated) {
            KeyTyper.typeAndReturn(data)
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard self.isLocked, LockState.isLocked else { return }
            self.failedTypings += 1
            if self.failedTypings >= 2 {
                // Mot de passe probablement changé : on arrête pour ne pas bloquer le compte.
                self.disarm()
                self.phase = .paused("Mot de passe refusé : enregistre-le à nouveau")
            } else {
                self.phase = .failed("Mot de passe refusé ?")
            }
        }
    }
}
