import AppKit
import Combine

/// Crée un notch sur l'écran principal (celui qui a un notch) ou sur tous les écrans,
/// et relie les services communs (mises à jour, raccourci, paroles).
@MainActor
final class NotchCoordinator {
    static let shared = NotchCoordinator()

    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    var viewModels: [NotchViewModel] { controllers.values.map(\.viewModel) }

    /// Le notch de l'écran sous la souris, sinon celui de l'écran principal.
    var activeViewModel: NotchViewModel? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let controller = controllers[screen.displayID] {
            return controller.viewModel
        }
        if let primary = NotchGeometry.targetScreen(), let controller = controllers[primary.displayID] {
            return controller.viewModel
        }
        return controllers.values.first?.viewModel
    }

    func start() {
        rebuild()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        AppSettings.shared.$showOnAllScreens
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.rebuild() } }
            }
            .store(in: &cancellables)

        // Paroles du morceau en cours (une seule fois, pas par écran)
        MediaController.shared.$track
            .removeDuplicates()
            .sink { LyricsService.shared.load(for: $0) }
            .store(in: &cancellables)

        // Mise à jour automatique : HUD « ↓ vX.Y.Z » dans le notch avant le redémarrage.
        UpdateChecker.shared.onWillInstall = { [weak self] version in
            for vm in self?.viewModels ?? [] {
                vm.close()
                vm.showHUD(.update(version), duration: 3)
            }
        }
        UpdateChecker.shared.start()

        // Raccourci global ⌥⌘N
        HotKeyService.shared.onPress = { [weak self] in self?.activeViewModel?.toggle() }
        HotKeyService.shared.register()

        // Touches volume / luminosité → HUD du notch
        MediaKeyService.shared.start()
    }

    func closeAll() {
        for vm in viewModels { vm.close() }
    }

    private func rebuild() {
        let targets: [NSScreen] = AppSettings.shared.showOnAllScreens
            ? NSScreen.screens
            : [NotchGeometry.targetScreen()].compactMap { $0 }
        let ids = Set(targets.map(\.displayID))

        for (id, controller) in controllers where !ids.contains(id) {
            controller.teardown()
            controllers[id] = nil
        }
        for screen in targets {
            if let controller = controllers[screen.displayID] {
                controller.layout()
            } else {
                let controller = NotchWindowController(screenID: screen.displayID)
                controller.show()
                controllers[screen.displayID] = controller
            }
        }
    }
}
