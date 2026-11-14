import AppKit
import ImageIO
import UniformTypeIdentifiers

/// « Étagère » : fichiers déposés dans le notch, gardés à portée de main.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [URL] = []
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?
    private let key = "shelf.paths"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func copyToPasteboard(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    // MARK: - Outils

    /// Dossier où sont rangés les fichiers créés depuis l'étagère.
    static var workFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("NotchFlow/Étagère", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    var images: [URL] { items.filter(Self.isImage) }

    /// Compresse les éléments en une archive .zip ajoutée à l'étagère.
    func zip(_ urls: [URL]) {
        guard !urls.isEmpty, !isWorking else { return }
        isWorking = true
        lastError = nil
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Archive (\(urls.count) éléments)"
        let destination = Self.uniqueURL(Self.workFolder.appendingPathComponent(name).appendingPathExtension("zip"))
        Task {
            let ok = await Self.makeZip(urls, to: destination)
            self.isWorking = false
            if ok { self.add([destination]) } else { self.lastError = "Compression impossible" }
        }
    }

    nonisolated private static func makeZip(_ urls: [URL], to destination: URL) async -> Bool {
        let fm = FileManager.default
        if urls.count == 1 {
            _ = await QuickActions.output("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, destination.path])
            return fm.fileExists(atPath: destination.path)
        }
        // Plusieurs éléments : copie (clone APFS, instantané) dans un dossier temporaire
        let staging = fm.temporaryDirectory.appendingPathComponent("notchflow-zip-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for url in urls {
                try fm.copyItem(at: url, to: uniqueURL(staging.appendingPathComponent(url.lastPathComponent)))
            }
        } catch {
            return false
        }
        _ = await QuickActions.output("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, destination.path])
        return fm.fileExists(atPath: destination.path)
    }

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png, jpeg, heic, tiff
        static var allCases: [ImageFormat] { [.png, .jpeg, .heic] }
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
        var type: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .heic: .heic
            case .tiff: .tiff
            }
        }
        var fileExtension: String { self == .jpeg ? "jpg" : self == .tiff ? "tiff" : rawValue }
    }

    /// Convertit et / ou réduit des images. `maxPixels` = plus grand côté, `scale` = facteur (0,5…).
    func convertImages(_ urls: [URL], to format: ImageFormat? = nil, maxPixels: Int? = nil, scale: Double? = nil) {
        let images = urls.filter(Self.isImage)
        guard !images.isEmpty, !isWorking else { return }
        isWorking = true
        lastError = nil
        let folder = Self.workFolder
        Task {
            var created: [URL] = []
            for url in images {
                if let out = await Self.processImage(url, folder: folder, format: format, maxPixels: maxPixels, scale: scale) {
                    created.append(out)
                }
            }
            self.isWorking = false
            if created.isEmpty { self.lastError = "Conversion impossible" } else { self.add(created) }
        }
    }

    nonisolated private static func processImage(_ url: URL, folder: URL, format: ImageFormat?, maxPixels: Int?, scale: Double?) async -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let longest = max(width, height)

        var target: Int?
        if let maxPixels, longest > maxPixels { target = maxPixels }
        if let scale, longest > 0 { target = max(1, Int(Double(longest) * scale)) }

        let image: CGImage?
        if let target {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: target,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }

        let sourceType = UTType(filenameExtension: url.pathExtension) ?? .png
        let outFormat = format ?? (sourceType.conforms(to: .jpeg) ? .jpeg : sourceType.conforms(to: .heic) ? .heic : .png)
        var base = url.deletingPathExtension().lastPathComponent
        if target != nil { base += " (\(image.width) px)" }
        let destinationURL = uniqueURL(folder.appendingPathComponent(base).appendingPathExtension(outFormat.fileExtension))

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, outFormat.type.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        // L'orientation est déjà appliquée par la miniature ; sinon on garde celle d'origine.
        var imageProps = options
        if target == nil, let orientation = props[kCGImagePropertyOrientation] { imageProps[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, imageProps as CFDictionary)
        return CGImageDestinationFinalize(destination) ? destinationURL : nil
    }

    /// Convertisseur intégré : PDF, documents, audio, vidéo (les images passent par `convertImages`).
    func convert(_ urls: [URL], to target: FileConverter.Target) {
        switch target {
        case .image(let format): convertImages(urls, to: format); return
        case .imageTIFF: convertImages(urls, to: .tiff); return
        default: break
        }
        guard !urls.isEmpty, !isWorking else { return }
        isWorking = true
        lastError = nil
        let folder = Self.workFolder
        Task {
            let created = await FileConverter.convert(urls, to: target, folder: folder)
            self.isWorking = false
            if created.isEmpty { self.lastError = "Conversion impossible" } else { self.add(created) }
        }
    }

    nonisolated static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        for i in 2...999 {
            let candidate = folder.appendingPathComponent("\(base) \(i)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}
