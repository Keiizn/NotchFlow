import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Démarrage des services (singletons)
        _ = MediaController.shared
        _ = BatteryService.shared
        _ = VolumeService.shared
        _ = CalendarService.shared
        _ = ClipboardService.shared
        _ = ShelfStore.shared
        _ = TimerService.shared
        _ = AppLauncher.shared
        _ = NotesStore.shared
        _ = BrightnessService.shared
        _ = RemindersService.shared
        _ = QuickActions.shared
        _ = BatteryManager.shared
        WeatherService.shared.start()
        BluetoothService.shared.start()
        PrivacyMonitor.shared.start()
        DownloadMonitor.shared.start()
        ScreenshotWatcher.shared.start()

        setupStatusItem()
        NotchCoordinator.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Rend la gestion de charge à macOS si l'utilisateur l'a demandé.
        BatteryManager.shared.restoreForQuit()
    }

    // MARK: - Barre des menus

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "NotchFlow")

        let menu = NSMenu()
        menu.addItem(withTitle: "Ouvrir le notch", action: #selector(openNotch), keyEquivalent: "")
        menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter NotchFlow", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc func openNotch() {
        NotchCoordinator.shared.activeViewModel?.open()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(AppSettings.shared))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Réglages NotchFlow"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 780, height: 560))
            window.center()
            settingsWindow = window
        }
        NotchCoordinator.shared.closeAll()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Ouvre « À propos » (qui lance la vérification) dans les réglages.
    @objc func checkForUpdates() {
        UpdateChecker.shared.check()
        openSettings()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}
