import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers

/// Convertisseur de fichiers intégré à l'étagère : images, PDF, documents, audio, vidéo.
enum FileConverter {
    enum Kind: String, CaseIterable {
        case image, pdf, document, audio, video
        var title: String {
            switch self {
            case .image: "Images"
            case .pdf: "PDF"
            case .document: "Documents"
            case .audio: "Audio"
            case .video: "Vidéo"
            }
        }
    }

    enum Target: Hashable, Identifiable {
        case image(ShelfStore.ImageFormat)
        case imageTIFF
        case imagesToPDF
        case pdfToPNG, pdfToText, mergePDF
        case document(String)        // txt, rtf, docx, html, odt
        case documentToPDF
        case audio(String)           // m4a, wav, aiff, caf
        case videoMP4, videoMOV, video720, videoAudio

        var id: String { title }

        var title: String {
            switch self {
            case .image(let f): "Image \(f.title)"
            case .imageTIFF: "Image TIFF"
            case .imagesToPDF: "Assembler en un PDF"
            case .pdfToPNG: "Pages en images PNG"
            case .pdfToText: "Texte brut (.txt)"
            case .mergePDF: "Fusionner les PDF"
            case .document(let ext): ext == "docx" ? "Word (.docx)" : ext == "odt" ? "OpenDocument (.odt)" : ".\(ext)"
            case .documentToPDF: "PDF"
            case .audio(let ext): ext == "m4a" ? "AAC (.m4a)" : ".\(ext)"
            case .videoMP4: "MP4 (H.264)"
            case .videoMOV: "MOV"
            case .video720: "Réduire en 720p"
            case .videoAudio: "Extraire l'audio (.m4a)"
            }
        }
    }

    private static let documentExtensions: Set<String> = ["txt", "text", "md", "rtf", "rtfd", "doc", "docx", "odt", "html", "htm", "webarchive", "wordml"]

    static func kind(of url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        if documentExtensions.contains(ext) { return .document }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    static func targets(for kind: Kind, count: Int) -> [Target] {
        switch kind {
        case .image: ShelfStore.ImageFormat.allCases.map { .image($0) } + [.imageTIFF, .imagesToPDF]
        case .pdf: [.pdfToPNG, .pdfToText] + (count > 1 ? [.mergePDF] : [])
        case .document: ["txt", "rtf", "docx", "html", "odt"].map { .document($0) } + [.documentToPDF]
        case .audio: ["m4a", "wav", "aiff", "caf"].map { .audio($0) }
        case .video: [.videoMP4, .videoMOV, .video720, .videoAudio]
        }
    }

    // MARK: - Conversion

    /// Convertit les fichiers et renvoie les fichiers créés.
    @MainActor
    static func convert(_ urls: [URL], to target: Target, folder: URL) async -> [URL] {
        switch target {
        case .image, .imageTIFF:
            return [] // géré par ShelfStore.convertImages
        case .imagesToPDF:
            return makePDF(fromImages: urls, folder: folder).map { [$0] } ?? []
        case .mergePDF:
            return mergePDFs(urls, folder: folder).map { [$0] } ?? []
        case .pdfToPNG:
            return urls.flatMap { pdfToImages($0, folder: folder) }
        case .pdfToText:
            return urls.compactMap { pdfToText($0, folder: folder) }
        case .document(let ext):
            var out: [URL] = []
            for url in urls {
                let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(ext))
                let format = ext == "txt" ? "txt" : ext
                _ = await QuickActions.output("/usr/bin/textutil", ["-convert", format, "-output", dest.path, url.path])
                if FileManager.default.fileExists(atPath: dest.path) { out.append(dest) }
            }
            return out
        case .documentToPDF:
            return urls.compactMap { documentToPDF($0, folder: folder) }
        case .audio(let ext):
            var out: [URL] = []
            let args: [String] = switch ext {
            case "m4a": ["-f", "m4af", "-d", "aac", "-b", "256000"]
            case "wav": ["-f", "WAVE", "-d", "LEI16"]
            case "aiff": ["-f", "AIFF", "-d", "BEI16"]
            default: ["-f", "caff", "-d", "LEI16"]
            }
            for url in urls {
                let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension(ext))
                _ = await QuickActions.output("/usr/bin/afconvert", args + [url.path, dest.path])
                if FileManager.default.fileExists(atPath: dest.path) { out.append(dest) }
            }
            return out
        case .videoMP4, .videoMOV, .video720, .videoAudio:
            var out: [URL] = []
            for url in urls {
                if let dest = await exportVideo(url, target: target, folder: folder) { out.append(dest) }
            }
            return out
        }
    }

    // MARK: - PDF

    @MainActor
    private static func makePDF(fromImages urls: [URL], folder: URL) -> URL? {
        let document = PDFDocument()
        for url in urls {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
            document.insert(page, at: document.pageCount)
        }
        guard document.pageCount > 0 else { return nil }
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Images (\(document.pageCount) pages)"
        let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(name).appendingPathExtension("pdf"))
        return document.write(to: dest) ? dest : nil
    }

    @MainActor
    private static func mergePDFs(_ urls: [URL], folder: URL) -> URL? {
        let merged = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) { merged.insert(page, at: merged.pageCount) }
            }
        }
        guard merged.pageCount > 0 else { return nil }
        let dest = ShelfStore.uniqueURL(folder.appendingPathComponent("PDF fusionné").appendingPathExtension("pdf"))
        return merged.write(to: dest) ? dest : nil
    }

    @MainActor
    private static func pdfToImages(_ url: URL, folder: URL) -> [URL] {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return [] }
        let base = url.deletingPathExtension().lastPathComponent
        // Plus de 6 pages : on range les images dans un dossier.
        var target = folder
        if doc.pageCount > 6 {
            target = ShelfStore.uniqueURL(folder.appendingPathComponent("\(base) – pages"))
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }
        var out: [URL] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let image = page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let dest = ShelfStore.uniqueURL(target.appendingPathComponent("\(base) – page \(i + 1)").appendingPathExtension("png"))
            if (try? png.write(to: dest)) != nil { out.append(dest) }
        }
        return doc.pageCount > 6 ? (out.isEmpty ? [] : [target]) : out
    }

    @MainActor
    private static func pdfToText(_ url: URL, folder: URL) -> URL? {
        guard let text = PDFDocument(url: url)?.string, !text.isEmpty else { return nil }
        let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("txt"))
        return (try? text.write(to: dest, atomically: true, encoding: .utf8)) != nil ? dest : nil
    }

    /// Document texte (txt, rtf, docx, html…) → PDF A4 paginé.
    @MainActor
    private static func documentToPDF(_ url: URL, folder: URL) -> URL? {
        guard let text = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else { return nil }
        let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("pdf"))

        let printInfo = NSPrintInfo(dictionary: [.jobSavingURL: dest])
        printInfo.paperSize = NSSize(width: 595, height: 842)   // A4
        printInfo.topMargin = 56; printInfo.bottomMargin = 56
        printInfo.leftMargin = 56; printInfo.rightMargin = 56
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.jobDisposition = .save

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    // MARK: - Vidéo

    private static func exportVideo(_ url: URL, target: Target, folder: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        let (preset, type, ext, suffix): (String, AVFileType, String, String) = switch target {
        case .videoMOV: (AVAssetExportPresetPassthrough, .mov, "mov", "")
        case .video720: (AVAssetExportPreset1280x720, .mp4, "mp4", " (720p)")
        case .videoAudio: (AVAssetExportPresetAppleM4A, .m4a, "m4a", "")
        default: (AVAssetExportPresetHighestQuality, .mp4, "mp4", "")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }
        let base = url.deletingPathExtension().lastPathComponent + suffix
        let dest = ShelfStore.uniqueURL(folder.appendingPathComponent(base).appendingPathExtension(ext))
        session.outputURL = dest
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        return session.status == .completed ? dest : nil
    }
}
