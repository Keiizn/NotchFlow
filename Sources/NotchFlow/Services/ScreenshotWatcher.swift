import Foundation
import Combine

/// Envoie les nouvelles captures d'écran dans l'étagère (via Spotlight : kMDItemIsScreenCapture).
@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    let captured = PassthroughSubject<URL, Never>()

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var startedAt = Date()
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        AppSettings.shared.$screenshotsToShelf
            .removeDuplicates()
            .sink { [weak self] enabled in enabled ? self?.startQuery() : self?.stopQuery() }
            .store(in: &cancellables)
    }

    private func startQuery() {
        guard query == nil else { return }
        startedAt = Date()
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] note in
            let added = (note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated { self?.handle(paths) }
        }
        query.start()
        self.query = query
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func handle(_ paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            // Seulement les captures prises après l'activation (pas tout l'historique).
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard created > startedAt, FileManager.default.fileExists(atPath: path) else { continue }
            ShelfStore.shared.add([url])
            captured.send(url)
        }
    }
}
