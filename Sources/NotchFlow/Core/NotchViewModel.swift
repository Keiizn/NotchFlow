import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class NotchViewModel: ObservableObject {
    enum State { case closed, open }

    enum Tab: String, CaseIterable, Identifiable {
        case home, battery, apps, shelf, timer, reminders, actions, notes, clipboard, system, mirror
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: "house.fill"
            case .battery: "battery.100.bolt"
            case .apps: "square.grid.3x3.fill"
            case .shelf: "tray.full.fill"
            case .timer: "timer"
            case .reminders: "checklist"
            case .actions: "bolt.fill"
            case .notes: "note.text"
            case .clipboard: "doc.on.clipboard.fill"
            case .system: "cpu"
            case .mirror: "camera.fill"
            }
        }
        var title: String {
            switch self {
            case .home: "Accueil"
            case .battery: "Batterie"
            case .apps: "Applications"
            case .shelf: "Étagère"
            case .timer: "Minuteur"
            case .reminders: "Rappels"
            case .actions: "Actions rapides"
            case .notes: "Notes rapides"
            case .clipboard: "Presse-papiers"
            case .system: "Système"
            case .mirror: "Miroir"
            }
        }
        var subtitle: String {
            switch self {
            case .home: "Musique, agenda et météo"
            case .battery: "Limite de charge, décharge, santé de la batterie"
            case .apps: "Lanceur d'apps favorites et apps ouvertes"
            case .shelf: "Déposez des fichiers, partagez-les par AirDrop"
            case .timer: "Minuteur et Pomodoro"
            case .reminders: "Rappels du jour, à cocher depuis le notch"
            case .actions: "Verrouiller, mode sombre, anti-veille, Raccourcis…"
            case .notes: "Bloc-notes toujours sous la main"
            case .clipboard: "Historique des textes copiés"
            case .system: "Processeur, mémoire, disque, batterie"
            case .mirror: "Aperçu de la caméra"
            }
        }
    }

    /// Onglets affichés, dans l'ordre canonique.
    var visibleTabs: [Tab] {
        let tabs = Tab.allCases.filter { settings.isTabEnabled($0.rawValue) }
        return tabs.isEmpty ? [.home] : tabs
    }

    /// Notifications éphémères affichées autour du notch fermé.
    enum HUD: Equatable {
        case volume(Float, Bool)   // niveau, muet
        case charging(Int)
        case unplugged(Int)
        case timerDone
        case update(String)        // nouvelle version en cours d'installation
        case brightness(Float)
        case reminder(String)
        case chargeLimited(Int)    // charge limitée à X %
    }

    /// Affiche les paroles à la place de l'agenda sur l'accueil.
    @Published var showLyrics = false

    /// Ce que le notch fermé affiche (« Live Activity »).
    enum Activity: Equatable {
        case none, music, timer, event
        case hud(HUD)
    }

    /// Taille fixe de la fenêtre transparente (assez grande pour l'état ouvert).
    let windowSize = CGSize(width: 880, height: 340)

    @Published private(set) var state: State = .closed
    @Published var tab: Tab = .home
    @Published private(set) var hud: HUD?
    @Published private(set) var isHovering = false
    @Published var isDropTargeted = false
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasPhysicalNotch = false

    private var screenFrame: CGRect = .zero
    private var hasEnteredOpenZone = false

    private let settings = AppSettings.shared
    private let media = MediaController.shared
    private let timer = TimerService.shared
    private let calendar = CalendarService.shared
    private let battery = BatteryService.shared
    private let volumeService = VolumeService.shared

    private var cancellables = Set<AnyCancellable>()
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var hudTask: Task<Void, Never>?

    var isOpen: Bool { state == .open }

    init() {
        // Toute modification d'un service qui influe sur la géométrie redessine le notch.
        Publishers.MergeMany([
            settings.objectWillChange,
            media.objectWillChange,
            timer.objectWillChange,
            calendar.objectWillChange,
        ])
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &cancellables)

        volumeService.changes
            .sink { [weak self] in
                guard let self, self.settings.showVolumeHUD else { return }
                self.showHUD(.volume(self.volumeService.volume, self.volumeService.isMuted))
            }
            .store(in: &cancellables)

        battery.events
            .sink { [weak self] event in
                guard let self, self.settings.showBatteryActivity else { return }
                switch event {
                case .pluggedIn(let level):
                    let manager = BatteryManager.shared
                    let limit = self.settings.chargeLimit
                    if manager.isLimiterActive && !manager.topUpActive && level >= limit - self.settings.sailingRange {
                        self.showHUD(.chargeLimited(limit), duration: 2.6)
                    } else {
                        self.showHUD(.charging(level), duration: 2.6)
                    }
                case .unplugged(let level): self.showHUD(.unplugged(level))
                }
            }
            .store(in: &cancellables)

        timer.finished
            .sink { [weak self] in self?.showHUD(.timerDone, duration: 4) }
            .store(in: &cancellables)

        BrightnessService.shared.changes
            .sink { [weak self] in
                guard let self, self.settings.showVolumeHUD else { return }
                self.showHUD(.brightness(BrightnessService.shared.brightness))
            }
            .store(in: &cancellables)

        BatteryManager.shared.limitReached
            .sink { [weak self] limit in
                guard let self, self.settings.showBatteryActivity else { return }
                self.showHUD(.chargeLimited(limit), duration: 3)
            }
            .store(in: &cancellables)

        RemindersService.shared.dueEvents
            .sink { [weak self] title in
                guard let self, self.settings.showReminderActivity else { return }
                self.showHUD(.reminder(title), duration: 6)
            }
            .store(in: &cancellables)

        // Paroles du morceau en cours
        media.$track
            .removeDuplicates()
            .sink { LyricsService.shared.load(for: $0) }
            .store(in: &cancellables)
    }

    // MARK: - Écran

    func updateScreen(_ screen: NSScreen) {
        screenFrame = screen.frame
        hasPhysicalNotch = NotchGeometry.hasNotch(screen)
        notchSize = NotchGeometry.notchSize(for: screen)
    }

    // MARK: - Géométrie

    var activity: Activity {
        if let hud { return .hud(hud) }
        if timer.isActive { return .timer }
        if settings.showEventActivity, calendar.upcomingSoon != nil { return .event }
        if settings.showMusicActivity, media.track != nil, media.isPlaying { return .music }
        return .none
    }

    func sideWidth(for activity: Activity) -> CGFloat {
        switch activity {
        case .none: 0
        case .music: notchSize.height + 4
        case .timer: 62
        case .event: 74
        case .hud(.reminder): 130
        case .hud: 86
        }
    }

    private var closedEarRadius: CGFloat { settings.style == .notch ? 6 : 0 }
    private var openEarRadius: CGFloat { settings.style == .notch ? 14 : 0 }

    var earRadius: CGFloat { isOpen ? openEarRadius : closedEarRadius }
    var bottomRadius: CGFloat { isOpen ? 28 : 12 }

    /// Décalage vertical : l'île flotte sous le bord de l'écran si aucun notch physique.
    var topOffset: CGFloat { settings.style == .island && !hasPhysicalNotch ? 6 : 0 }

    var closedSize: CGSize {
        // Au survol, le notch s'élargit et s'allonge légèrement (comme sur iPhone),
        // sans déformer son contenu.
        let grow = isHovering && settings.hoverGrow
        return CGSize(
            width: notchSize.width + 2 * closedEarRadius + 2 * sideWidth(for: activity) + (grow ? 14 : 0),
            height: notchSize.height + (grow ? 5 : 0)
        )
    }

    /// Ouverture : ressort vif avec un tout petit dépassement, comme la Dynamic Island.
    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    /// Fermeture / survol / activités : plus amorti, sans rebond.
    static let closeSpring = Animation.spring(response: 0.34, dampingFraction: 0.95)

    var openSize: CGSize {
        CGSize(width: CGFloat(settings.openWidth), height: notchSize.height + CGFloat(settings.openHeight))
    }

    var shapeSize: CGSize { isOpen ? openSize : closedSize }

    private func screenRect(for size: CGSize) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - topOffset,
            width: size.width,
            height: size.height + topOffset
        )
    }

    // MARK: - Souris

    func handleMouse(at point: CGPoint, dragging: Bool) {
        switch state {
        case .closed:
            let zone = screenRect(for: closedSize).insetBy(dx: -8, dy: -4)
            if zone.contains(point) {
                if !isHovering { isHovering = true }
                if dragging {
                    if dragContainsFiles() { open(tab: .shelf) }
                } else if settings.openOnHover && !isInteractiveHUD {
                    scheduleOpen()
                }
            } else {
                cancelOpen()
            }
        case .open:
            let zone = screenRect(for: openSize).insetBy(dx: -16, dy: -16)
            if zone.contains(point) || isDropTargeted {
                hasEnteredOpenZone = true
                cancelClose()
            } else {
                scheduleClose()
            }
        }
    }

    func handleClickOutside(at point: CGPoint) {
        guard isOpen, settings.closeOnClickOutside, !screenRect(for: openSize).contains(point) else { return }
        close()
    }

    private func dragContainsFiles() -> Bool {
        NSPasteboard(name: .drag).types?.contains(.fileURL) ?? false
    }

    private func scheduleOpen() {
        guard openTask == nil else { return }
        let delay = settings.hoverDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            self.open()
        }
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
        if isHovering { isHovering = false }
    }

    private func scheduleClose() {
        guard closeTask == nil, hasEnteredOpenZone else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.35))
            guard let self, !Task.isCancelled else { return }
            self.closeTask = nil
            self.close()
        }
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    // MARK: - Ouverture / fermeture

    func open(tab: Tab? = nil) {
        cancelOpen()
        cancelClose()
        if let tab { self.tab = tab }
        if !visibleTabs.contains(self.tab) { self.tab = visibleTabs[0] }
        guard state != .open else { return }
        hasEnteredOpenZone = screenRect(for: openSize).insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation)
        hudTask?.cancel()
        withAnimation(Self.openSpring) {
            hud = nil
            state = .open
        }
        if settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func close() {
        cancelClose()
        guard state == .open else { return }
        withAnimation(Self.closeSpring) {
            state = .closed
            isHovering = false
        }
    }

    func toggle() { isOpen ? close() : open() }

    // MARK: - HUD

    /// HUD avec curseur affiché : le survol ne doit pas ouvrir le notch.
    private var isInteractiveHUD: Bool {
        switch hud {
        case .some(.volume), .some(.brightness): true
        default: false
        }
    }

    func showHUD(_ kind: HUD, duration: Double = 1.8) {
        guard state == .closed else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { hud = kind }
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { self.hud = nil }
        }
    }

    // MARK: - Glisser-déposer

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            handled = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in ShelfStore.shared.add([url]) }
            }
        }
        if handled { open(tab: .shelf) }
        return handled
    }
}
