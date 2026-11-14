import AppKit
import UniformTypeIdentifiers

/// Apps favorites (configurables) et apps actuellement ouvertes.
@MainActor
final class AppLauncher: ObservableObject {
    static let shared = AppLauncher()

    struct AppItem: Identifiable, Equatable {
        let url: URL
        var id: String { url.path }
        var name: String { FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "") }
    }

    @Published private(set) var running: [NSRunningApplication] = []
    private let settings = AppSettings.shared

    var favorites: [AppItem] {
        settings.favoriteApps
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(AppItem.init)
    }

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
        refreshRunning()
    }

    func refreshRunning() {
        running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }

    func isRunning(_ item: AppItem) -> Bool {
        running.contains { $0.bundleURL?.standardizedFileURL == item.url.standardizedFileURL }
    }

    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func launch(_ item: AppItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: item.url, configuration: configuration)
    }

    func activate(_ app: NSRunningApplication) {
        app.activate()
    }

    func quit(_ app: NSRunningApplication) {
        app.terminate()
    }

    // MARK: - Gestion des favoris

    func addFavorites(_ urls: [URL]) {
        var list = settings.favoriteApps
        for url in urls where url.pathExtension == "app" && !list.contains(url.path) {
            list.append(url.path)
        }
        settings.favoriteApps = list
    }

    func removeFavorite(_ item: AppItem) {
        settings.favoriteApps.removeAll { $0 == item.url.path }
    }

    func moveFavorite(from source: IndexSet, to destination: Int) {
        settings.favoriteApps.move(fromOffsets: source, toOffset: destination)
    }

    func pinRunning(_ app: NSRunningApplication) {
        if let url = app.bundleURL { addFavorites([url]) }
    }

    /// Ouvre un sélecteur de fichiers pour choisir des applications.
    func pickApps() {
        let panel = NSOpenPanel()
        panel.title = "Ajouter des applications"
        panel.prompt = "Ajouter"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            addFavorites(panel.urls)
        }
    }
}
