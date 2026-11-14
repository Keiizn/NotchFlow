import AppKit
import Combine
import IOKit
import IOKit.pwr_mgt

/// Santé et mesures détaillées de la batterie (registre IOKit « AppleSmartBattery », sans droits admin).
struct BatteryHealth: Equatable {
    var cycleCount: Int = 0
    var designCapacity: Int = 0      // mAh
    var maxCapacity: Int = 0         // mAh (capacité réelle actuelle)
    var currentCapacity: Int = 0     // mAh
    var temperature: Double = 0      // °C
    var voltage: Double = 0          // V
    var amperage: Double = 0         // A (négatif = décharge)
    var adapterWatts: Int = 0
    var adapterName: String = ""

    var healthPercent: Int {
        designCapacity > 0 ? Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded()) : 0
    }

    /// Puissance entrant (+) ou sortant (−) de la batterie, en watts.
    var batteryWatts: Double { voltage * amperage }
}

/// Gestion de charge façon AlDente : limite de charge avec marge, décharge forcée,
/// charge ponctuelle à 100 %, protection thermique.
///
/// Les écritures SMC passent par l'assistant `notchflow-smc` (root via sudoers).
@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    enum HelperState: Equatable {
        case checking
        case notInstalled
        case outdated
        case ready
        case unsupported
    }

    enum Mode: Equatable {
        case onBattery
        case charging
        case limitReached      // charge en pause : limite atteinte
        case sailing           // dans la marge : on laisse la batterie redescendre doucement
        case discharging       // décharge forcée vers la limite
        case tooHot            // charge en pause : batterie trop chaude
        case full
        case notManaged
    }

    @Published private(set) var helperState: HelperState = .checking
    @Published private(set) var health = BatteryHealth()
    @Published private(set) var chargingInhibited = false
    @Published private(set) var adapterDisabled = false
    @Published private(set) var mode: Mode = .notManaged
    /// Charge ponctuelle jusqu'à 100 % (ignore la limite jusqu'au plein).
    @Published var topUpActive = false { didSet { evaluate() } }
    @Published private(set) var lastError: String?
    /// Clés SMC utilisées et état réel lu dans le SMC (diagnostic).
    @Published private(set) var smcKeys = ""
    @Published private(set) var smcCharging = "?"
    @Published private(set) var smcAdapter = "?"
    @Published private(set) var preventingSleep = false

    /// Émis quand la limite est atteinte (pour la Live Activity).
    let limitReached = PassthroughSubject<Int, Never>()

    static let helperVersion = "2"
    static let installedHelper = "/usr/local/libexec/notchflow-smc"
    static var bundledHelper: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/notchflow-smc").path
    }

    private let settings = AppSettings.shared
    private let battery = BatteryService.shared
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isApplying = false
    private var pendingEvaluate = false
    private var sleepAssertion: IOPMAssertionID = 0

    var isLimiterActive: Bool { settings.chargeLimiterEnabled && helperState == .ready }

    private init() {
        refreshHealth()

        // Réévalue à chaque changement de niveau / branchement, et toutes les 20 s.
        battery.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshHealth()
                    self?.evaluate()
                }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.evaluate() } }
            .store(in: &cancellables)

        // Toutes les 15 s : santé + resynchronisation avec l'état RÉEL du SMC
        // (le firmware peut réactiver la charge tout seul, notamment après la veille).
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshHealth()
                self?.syncWithSMC()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Le SMC peut avoir été réinitialisé pendant la veille : on relit son état.
            MainActor.assumeIsolated { self?.syncWithSMC(delay: 3) }
        }

        checkHelper()
    }

    // MARK: - Assistant (installation)

    func checkHelper() {
        helperState = .checking
        Task {
            guard FileManager.default.fileExists(atPath: Self.installedHelper) else {
                helperState = .notInstalled
                return
            }
            let version = await Self.run("/usr/bin/sudo", ["-n", Self.installedHelper, "version"])
            guard version.status == 0 else {
                helperState = .notInstalled
                return
            }
            guard version.output.trimmingCharacters(in: .whitespacesAndNewlines) == Self.helperVersion else {
                helperState = .outdated
                return
            }
            let status = await Self.run(Self.installedHelper, ["status"])
            if status.output.contains("charging_key=none") {
                helperState = .unsupported
                return
            }
            readStatus(status.output)
            helperState = .ready
            evaluate()
        }
    }

    /// Installe l'assistant (mot de passe administrateur demandé une seule fois).
    func installHelper() {
        let user = NSUserName()
        let source = Self.bundledHelper
        guard FileManager.default.fileExists(atPath: source) else {
            lastError = "Assistant introuvable dans l'app. Réinstallez NotchFlow."
            return
        }
        let shell = """
        set -e
        mkdir -p /usr/local/libexec
        cp \(Self.shellQuote(source)) \(Self.installedHelper)
        chown root:wheel \(Self.installedHelper)
        chmod 755 \(Self.installedHelper)
        TMP=$(mktemp)
        echo \(Self.shellQuote("\(user) ALL=(root) NOPASSWD: \(Self.installedHelper)")) > "$TMP"
        /usr/sbin/visudo -cf "$TMP"
        chown root:wheel "$TMP"
        chmod 440 "$TMP"
        mv "$TMP" /private/etc/sudoers.d/notchflow
        """
        runWithAdministratorPrivileges(shell) { [weak self] success in
            if success { self?.lastError = nil } else { self?.lastError = "Installation annulée ou refusée." }
            self?.checkHelper()
        }
    }

    /// Désinstalle l'assistant et rétablit la charge normale.
    func uninstallHelper() {
        let shell = """
        \(Self.installedHelper) charging on || true
        \(Self.installedHelper) adapter on || true
        rm -f \(Self.installedHelper) /private/etc/sudoers.d/notchflow
        """
        runWithAdministratorPrivileges(shell) { [weak self] _ in
            self?.chargingInhibited = false
            self?.adapterDisabled = false
            self?.settings.chargeLimiterEnabled = false
            self?.checkHelper()
        }
    }

    // MARK: - État réel du SMC

    private func readStatus(_ output: String) {
        func value(_ key: String) -> String? {
            output.split(separator: "\n").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
        }
        smcKeys = [value("charging_key"), value("adapter_key")].compactMap { $0 }.joined(separator: " / ")
        smcCharging = value("charging") ?? "?"
        smcAdapter = value("adapter") ?? "?"
        if smcCharging != "unknown" { chargingInhibited = smcCharging == "disabled" }
        if smcAdapter != "unknown" { adapterDisabled = smcAdapter == "disabled" }
    }

    /// Relit le SMC puis réapplique la logique si l'état a dérivé.
    func syncWithSMC(delay: Double = 0) {
        guard helperState == .ready else { evaluate(); return }
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !isApplying else { return }
            let status = await Self.run(Self.installedHelper, ["status"])
            if status.status == 0 { readStatus(status.output) }
            evaluate()
        }
    }

    // MARK: - Veille

    /// Avant la veille, NotchFlow ne peut plus surveiller la charge.
    private func prepareForSleep() {
        releaseSleepAssertion()
        guard helperState == .ready else { return }
        // Jamais de décharge forcée pendant la veille.
        if adapterDisabled {
            battery.suppressEventsUntil = Date().addingTimeInterval(8)
            runHelperSync(["adapter", "on"])
            adapterDisabled = false
        }
        guard isLimiterActive, !topUpActive else { return }
        switch settings.sleepCharging {
        case .stop, .preventSleep:
            // Sinon le Mac chargerait jusqu'à 100 % pendant la nuit.
            if !chargingInhibited {
                runHelperSync(["charging", "off"])
                chargingInhibited = true
            }
        case .allow:
            break
        }
    }

    /// Empêche la veille (sur secteur) tant que la batterie n'a pas atteint la limite.
    private func updateSleepAssertion() {
        let want = isLimiterActive && settings.sleepCharging == .preventSleep
            && battery.isPluggedIn && mode == .charging
        if want && sleepAssertion == 0 {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                "PreventSystemSleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchFlow : charge jusqu'à la limite" as CFString,
                &id
            )
            if result == kIOReturnSuccess { sleepAssertion = id }
        } else if !want {
            releaseSleepAssertion()
        }
        preventingSleep = sleepAssertion != 0
    }

    private func releaseSleepAssertion() {
        if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
        preventingSleep = false
    }

    // MARK: - Logique de charge

    func evaluate() {
        guard !isApplying else { pendingEvaluate = true; return }
        defer { updateSleepAssertion() }
        guard battery.hasBattery else {
            mode = .notManaged
            return
        }
        let level = battery.level
        // Adaptateur coupé par NotchFlow : macOS croit le Mac débranché, mais il ne l'est pas.
        // On continue donc la décharge jusqu'à la limite (si on débranche entre-temps, c'est sans effet).
        let plugged = battery.isPluggedIn || adapterDisabled

        guard isLimiterActive else {
            // Limiteur coupé : on rend la main à macOS si on avait modifié l'état.
            if helperState == .ready && (chargingInhibited || adapterDisabled) {
                apply(charging: true, adapter: true)
            }
            mode = plugged ? (battery.isCharging ? .charging : (level >= 100 ? .full : .notManaged)) : .onBattery
            return
        }

        if topUpActive && level >= 100 {
            topUpActive = false   // relance evaluate() via didSet
            return
        }

        let limit = topUpActive ? 100 : settings.chargeLimit
        let resumeBelow = topUpActive ? 100 : max(limit - settings.sailingRange, 5)
        let tooHot = settings.heatProtection && health.temperature >= settings.heatLimit && !topUpActive

        guard plugged else {
            // Sur batterie : rien à piloter, mais on relâche la décharge forcée.
            if adapterDisabled { apply(charging: !chargingInhibited, adapter: true) }
            mode = .onBattery
            return
        }

        var wantCharging = !chargingInhibited
        var wantAdapter = true

        if settings.dischargeToLimit && !topUpActive && level > limit {
            wantCharging = false
            wantAdapter = false
            mode = .discharging
        } else if tooHot {
            wantCharging = false
            mode = .tooHot
        } else if level >= limit {
            if !chargingInhibited && !topUpActive && lastError == nil {
                limitReached.send(limit)
            }
            wantCharging = false
            mode = limit >= 100 ? .full : .limitReached
        } else if level <= resumeBelow {
            wantCharging = true
            mode = .charging
        } else {
            // Entre (limite − marge) et la limite : on conserve l'état courant.
            mode = chargingInhibited ? .sailing : .charging
        }

        if wantCharging == chargingInhibited || wantAdapter == adapterDisabled {
            apply(charging: wantCharging, adapter: wantAdapter)
        }
    }

    private func apply(charging: Bool, adapter: Bool) {
        isApplying = true
        Task {
            var errors: [String] = []
            // Ordre sûr : on coupe la charge AVANT de couper l'adaptateur, et on rebranche
            // l'adaptateur AVANT de relancer la charge.
            if adapter && adapterDisabled {
                await setAdapter(true, errors: &errors)
            }
            if charging == chargingInhibited {
                let r = await Self.run("/usr/bin/sudo", ["-n", Self.installedHelper, "charging", charging ? "on" : "off"])
                if r.status == 0 { chargingInhibited = !charging } else { errors.append(r.output) }
            }
            if !adapter && !adapterDisabled {
                await setAdapter(false, errors: &errors)
            }
            // Relit l'état réel pour l'affichage et le diagnostic
            let status = await Self.run(Self.installedHelper, ["status"])
            if status.status == 0 { readStatus(status.output) }

            if errors.isEmpty {
                lastError = nil
            } else if errors.contains(where: { $0.contains("password") || $0.contains("sudo") }) {
                lastError = "Autorisation perdue : réinstallez l'assistant dans Réglages → Batterie."
            } else {
                lastError = "Le Mac a refusé la commande (\(errors.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "erreur")). Désactivez « Recharge optimisée » dans Réglages Système → Batterie."
            }
            isApplying = false
            if pendingEvaluate {
                pendingEvaluate = false
                evaluate()
            }
        }
    }

    private func setAdapter(_ enabled: Bool, errors: inout [String]) async {
        // macOS va signaler un faux débranchement / rebranchement : pas de HUD pour ça.
        battery.suppressEventsUntil = Date().addingTimeInterval(8)
        let r = await Self.run("/usr/bin/sudo", ["-n", Self.installedHelper, "adapter", enabled ? "on" : "off"])
        if r.status == 0 { adapterDisabled = !enabled } else { errors.append(r.output) }
    }

    /// Appelé à la fermeture de l'app : rend la charge à macOS (synchrone).
    func restoreForQuit() {
        releaseSleepAssertion()
        guard helperState == .ready else { return }
        // La décharge forcée est toujours arrêtée, même si l'option est désactivée.
        if adapterDisabled { runHelperSync(["adapter", "on"]) }
        if settings.restoreChargingOnQuit && chargingInhibited { runHelperSync(["charging", "on"]) }
    }

    private func runHelperSync(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", Self.installedHelper] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Santé (IOKit)

    func refreshHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else { return }

        func int(_ key: String) -> Int { (dict[key] as? NSNumber)?.intValue ?? 0 }

        var h = BatteryHealth()
        h.cycleCount = int("CycleCount")
        h.designCapacity = int("DesignCapacity")
        h.maxCapacity = int("AppleRawMaxCapacity") > 0 ? int("AppleRawMaxCapacity") : int("NominalChargeCapacity")
        h.currentCapacity = int("AppleRawCurrentCapacity")
        h.temperature = Double(int("Temperature")) / 100
        h.voltage = Double(int("Voltage")) / 1000
        h.amperage = Double((dict["Amperage"] as? NSNumber)?.int64Value ?? 0) / 1000
        if let adapter = dict["AdapterDetails"] as? [String: Any] {
            h.adapterWatts = (adapter["Watts"] as? NSNumber)?.intValue ?? 0
            h.adapterName = adapter["Name"] as? String ?? ""
        }
        if h != health { health = h }
    }

    // MARK: - Utilitaires

    private func runWithAdministratorPrivileges(_ shell: String, completion: @escaping @MainActor (Bool) -> Void) {
        let script = "do shell script \(Self.appleScriptString(shell)) with administrator privileges"
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let success = result != nil && error == nil
            Task { @MainActor in completion(success) }
        }
    }

    nonisolated static func run(_ path: String, _ arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }

    /// Entoure de guillemets simples pour le shell.
    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Chaîne littérale AppleScript.
    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
