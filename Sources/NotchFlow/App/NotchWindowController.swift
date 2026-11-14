import AppKit
import SwiftUI

/// Panneau transparent, sans bordure, posé au-dessus de la barre des menus.
/// Les zones totalement transparentes laissent passer les clics vers ce qui est dessous.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Empêche macOS de repousser la fenêtre sous la barre des menus.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func configure() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        // ⚠️ Ne pas utiliser `isFloatingPanel = true` : il remet le niveau à `.floating`,
        // sous la barre des menus, et les menus s'affichaient alors par-dessus le notch.
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        applyLevel()
    }

    /// Au-dessus de la barre des menus et des icônes d'état (niveau 24-25).
    func applyLevel() {
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    }

    override func orderFrontRegardless() {
        applyLevel()
        super.orderFrontRegardless()
    }
}

@MainActor
final class NotchWindowController {
    let viewModel = NotchViewModel()
    private var panel: NotchPanel?
    private var monitors: [Any] = []

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show() {
        let size = viewModel.windowSize
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.configure()

        let root = NotchRootView()
            .environmentObject(viewModel)
            .environmentObject(AppSettings.shared)
            .environmentObject(MediaController.shared)
            .environmentObject(CalendarService.shared)
            .environmentObject(BatteryService.shared)
            .environmentObject(WeatherService.shared)
            .environmentObject(ShelfStore.shared)
            .environmentObject(TimerService.shared)
            .environmentObject(ClipboardService.shared)
            .environmentObject(AppLauncher.shared)
            .environmentObject(NotesStore.shared)
            .environmentObject(SystemMonitor.shared)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.sizingOptions = []
        // Sans ça, SwiftUI décale tout le contenu sous le notch (zone de sécurité).
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        layout()
        panel.orderFrontRegardless()
        installMonitors()
    }

    /// Place la fenêtre en haut au centre de l'écran qui possède un notch (ou l'écran principal).
    func layout() {
        guard let panel, let screen = NotchGeometry.targetScreen() else { return }
        viewModel.updateScreen(screen)
        let size = viewModel.windowSize
        let frame = screen.frame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated {
                self?.viewModel.handleMouse(at: NSEvent.mouseLocation, dragging: dragging)
            }
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            let dragging = event.type == .leftMouseDragged
            MainActor.assumeIsolated {
                self?.viewModel.handleMouse(at: NSEvent.mouseLocation, dragging: dragging)
            }
            return event
        }) { monitors.append(local) }

        // Clic en dehors du notch ouvert → fermeture
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.handleClickOutside(at: NSEvent.mouseLocation)
            }
        }) { monitors.append(clicks) }
    }
}
