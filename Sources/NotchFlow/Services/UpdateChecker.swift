import AppKit

/// Vérifie la dernière Release GitHub et met l'app à jour automatiquement :
/// téléchargement → décompression → remplacement de l'app → redémarrage.
///
/// Un fichier téléchargé par l'app elle-même (URLSession) n'est pas mis en
/// quarantaine par macOS : la nouvelle version s'ouvre sans blocage Gatekeeper.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(version: String)
        case installing(version: String)
        case failed(String)
    }

    static let repository = "Keiizn/NotchFlow"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/install.sh | bash"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheck: Date?
    @Published private(set) var releaseNotes: String = ""

    /// Appelé juste avant le redémarrage (pour afficher un HUD dans le notch).
    var onWillInstall: ((String) -> Void)?

    private var timer: Timer?
    private let checkInterval: TimeInterval = 6 * 3600

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    private var pendingDownloadURL: URL?

    private init() {}

    // MARK: - Version installée

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var commit: String? {
        Bundle.main.infoDictionary?["NFCommit"] as? String
    }

    /// L'app peut-elle se remplacer elle-même (dossier accessible en écriture) ?
    static var canSelfUpdate: Bool {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else { return false }
        return FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
    }

    // MARK: - Planification

    func start() {
        guard timer == nil else { return }
        // Première vérification peu après le lancement, puis toutes les 6 h.
        Task {
            try? await Task.sleep(for: .seconds(20))
            self.automaticCheck()
        }
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.automaticCheck() }
        }
    }

    private func automaticCheck() {
        guard AppSettings.shared.autoCheckUpdates else { return }
        check(automatic: true)
    }

    // MARK: - Vérification

    func check(automatic: Bool = false) {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        status = .checking
        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    status = .failed("GitHub ne répond pas")
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
                lastCheck = Date()
                releaseNotes = release.body ?? ""

                guard Self.isNewer(latest, than: Self.version) else {
                    status = .upToDate
                    return
                }
                let asset = release.assets.first { $0.name == "NotchFlow.zip" }
                pendingDownloadURL = asset.flatMap { URL(string: $0.browser_download_url) }
                status = .available(version: latest)

                if automatic && AppSettings.shared.autoInstallUpdates && Self.canSelfUpdate {
                    installUpdate()
                }
            } catch {
                status = .failed("Pas de connexion à GitHub")
            }
        }
    }

    // MARK: - Installation

    /// Télécharge et installe la version disponible, puis redémarre l'app.
    /// Si l'app ne peut pas se remplacer elle-même, copie la commande d'installation.
    func installUpdate() {
        guard case .available(let version) = status else { return }
        guard Self.canSelfUpdate, let downloadURL = pendingDownloadURL else {
            copyInstallCommandAndOpenTerminal()
            return
        }
        status = .downloading(version: version)

        Task {
            do {
                let (tempZip, response) = try await URLSession.shared.download(from: downloadURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.message("Téléchargement impossible")
                }
                let workDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NotchFlowUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                let zip = workDir.appendingPathComponent("NotchFlow.zip")
                try FileManager.default.moveItem(at: tempZip, to: zip)

                status = .installing(version: version)
                try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.path])
                let newApp = workDir.appendingPathComponent("NotchFlow.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else {
                    throw UpdateError.message("Archive invalide")
                }

                onWillInstall?(version)
                try await Task.sleep(for: .seconds(2))
                try relaunch(replacingWith: newApp)
            } catch let UpdateError.message(text) {
                status = .failed(text)
            } catch {
                status = .failed("Échec de la mise à jour")
            }
        }
    }

    /// Lance un petit script détaché qui attend la fermeture de l'app, remplace le
    /// bundle, retire la quarantaine, re-signe et relance la nouvelle version.
    private func relaunch(replacingWith newApp: URL) throws {
        let destination = Bundle.main.bundleURL.path
        let script = """
        PID="$1"; NEW="$2"; DEST="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.old"
        if mv "$DEST" "$DEST.old" && mv "$NEW" "$DEST"; then
          rm -rf "$DEST.old"
        else
          [ -d "$DEST.old" ] && [ ! -d "$DEST" ] && mv "$DEST.old" "$DEST"
        fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        codesign --force --deep --sign - "$DEST" >/dev/null 2>&1
        open "$DEST"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "notchflow-updater",
                             String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination]
        try process.run()
        NSApp.terminate(nil)
    }

    func copyInstallCommandAndOpenTerminal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.installCommand, forType: .string)
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Utilitaires

    private enum UpdateError: Error { case message(String) }

    private static func run(_ path: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.message("Décompression impossible"))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Compare deux versions « 1.2.3 » composante par composante.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
