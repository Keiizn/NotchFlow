import Foundation
import Combine

/// Téléchargements en cours dans ~/Téléchargements (Safari, Chrome, Brave, Edge, Firefox, Arc…).
@MainActor
final class DownloadMonitor: ObservableObject {
    static let shared = DownloadMonitor()

    struct Item: Identifiable, Equatable {
        let id: String          // chemin du fichier partiel
        let name: String        // nom final
        var bytes: Int64
        var fraction: Double?   // nil = taille totale inconnue
    }

    @Published private(set) var active: [Item] = []
    let finished = PassthroughSubject<URL, Never>()

    /// Progression globale (moyenne des téléchargements dont la taille est connue).
    var overallFraction: Double? {
        let known = active.compactMap(\.fraction)
        return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
    }

    var totalBytes: Int64 { active.reduce(0) { $0 + $1.bytes } }

    private static let partialExtensions = ["download", "crdownload", "part", "opdownload"]

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private var timer: Timer?
    private var lastChange: [String: (bytes: Int64, date: Date)] = [:]
    private var progressByPath: [String: Progress] = [:]
    private var subscriber: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        AppSettings.shared.$showDownloadActivity
            .removeDuplicates()
            .sink { [weak self] enabled in enabled ? self?.startPolling() : self?.stopPolling() }
            .store(in: &cancellables)
    }

    private func startPolling() {
        guard timer == nil else { return }
        // Les navigateurs publient la progression de leurs fichiers (c'est ce qu'affiche le Finder).
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let path = progress.fileURL?.standardizedFileURL.path
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let path { self?.progressByPath[path] = progress }
                }
            }
            return {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let path { self?.progressByPath[path] = nil }
                    }
                }
            }
        }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        progressByPath = [:]
        lastChange = [:]
        active = []
    }

    private func scan() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
                                                        options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        var items: [Item] = []
        var seen = Set<String>()

        for url in entries where Self.partialExtensions.contains(url.pathExtension.lowercased()) {
            let path = url.standardizedFileURL.path
            seen.insert(path)
            let finalName = url.deletingPathExtension().lastPathComponent
            var bytes = Self.size(of: url)
            var fraction: Double?

            if url.pathExtension.lowercased() == "download" {
                // Paquet Safari : la progression est dans son Info.plist
                let plist = url.appendingPathComponent("Info.plist")
                if let dict = NSDictionary(contentsOf: plist) as? [String: Any] {
                    let soFar = (dict["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    let total = (dict["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value ?? 0
                    if soFar > 0 { bytes = soFar }
                    if total > 0 { fraction = min(1, Double(soFar) / Double(total)) }
                }
            }
            if fraction == nil, let progress = progressByPath[path] ?? progressByPath[url.deletingPathExtension().standardizedFileURL.path],
               progress.totalUnitCount > 0 {
                fraction = min(1, max(0, progress.fractionCompleted))
            }

            // Un fichier partiel qui ne grossit plus depuis 15 s est un téléchargement abandonné.
            if let previous = lastChange[path], previous.bytes == bytes {
                if now.timeIntervalSince(previous.date) > 15 { continue }
            } else {
                // Première fois vue : on part de la date de dernière écriture du fichier.
                let firstSeen = lastChange[path] == nil
                lastChange[path] = (bytes, firstSeen ? Self.modificationDate(of: url) : now)
                if firstSeen, now.timeIntervalSince(Self.modificationDate(of: url)) > 15 { continue }
            }
            items.append(Item(id: path, name: finalName, bytes: bytes, fraction: fraction))
        }

        // Téléchargements terminés : le fichier partiel a disparu et le fichier final existe.
        for item in active where !seen.contains(item.id) {
            let finalURL = folder.appendingPathComponent(item.name)
            lastChange[item.id] = nil
            guard fm.fileExists(atPath: finalURL.path) else { continue }
            finished.send(finalURL)
            if AppSettings.shared.downloadsToShelf {
                ShelfStore.shared.add([finalURL])
            }
        }
        for key in lastChange.keys where !seen.contains(key) { lastChange[key] = nil }

        items.sort { $0.name < $1.name }
        if items != active { active = items }
    }

    private static func modificationDate(of url: URL) -> Date {
        let candidates = [url, url.appendingPathComponent("Info.plist")]
        return candidates
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max() ?? .distantPast
    }

    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            // Paquet : somme des fichiers qu'il contient
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
            var total: Int64 = 0
            while let file = enumerator?.nextObject() as? URL {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }
        return Int64(values.fileSize ?? values.totalFileAllocatedSize ?? 0)
    }
}
