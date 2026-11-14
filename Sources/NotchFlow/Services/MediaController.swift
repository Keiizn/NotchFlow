import AppKit
import SwiftUI

enum MediaSource: String {
    case spotify, music

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    /// Nom AppleScript de l'application
    var appName: String { self == .spotify ? "Spotify" : "Music" }
    var displayName: String { self == .spotify ? "Spotify" : "Musique" }
    var notificationName: String {
        self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
    }
    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

struct Track: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double   // secondes
}

/// Lit et pilote Spotify / Apple Music via leurs notifications distribuées et AppleScript.
@MainActor
final class MediaController: ObservableObject {
    static let shared = MediaController()

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var source: MediaSource?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: Color = .white
    @Published private(set) var position: Double = 0
    private var positionDate = Date()

    private let scriptQueue = DispatchQueue(label: "app.notchflow.applescript", qos: .userInitiated)
    private var syncTimer: Timer?
    private var artworkKey: String?

    private init() {
        let center = DistributedNotificationCenter.default()
        for src in [MediaSource.spotify, .music] {
            center.addObserver(forName: Notification.Name(src.notificationName), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handleNotification(info, from: src) }
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let src = self.source, src.bundleID == bundleID else { return }
                self.clear()
            }
        }

        syncTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.periodicSync() }
        }
        refreshFromRunningApps()
    }

    // MARK: - Position

    func currentPosition(at date: Date) -> Double {
        guard let track else { return 0 }
        let p = isPlaying ? position + date.timeIntervalSince(positionDate) : position
        return track.duration > 0 ? min(max(p, 0), track.duration) : max(p, 0)
    }

    private func setPosition(_ value: Double) {
        position = value
        positionDate = Date()
    }

    // MARK: - Commandes

    func playPause() {
        let current = currentPosition(at: Date())
        send("playpause")
        isPlaying.toggle()
        setPosition(current)
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        send("set player position to \(Int(seconds))")
        setPosition(seconds)
    }

    func launch(_ src: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: src.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSourceApp() { launch(source ?? .spotify) }

    func isInstalled(_ src: MediaSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: src.bundleID) != nil
    }

    private func send(_ command: String) {
        guard let src = source ?? [MediaSource.spotify, .music].first(where: { $0.isRunning }) else { return }
        run("tell application \"\(src.appName)\" to \(command)") { [weak self] _ in
            self?.fetchState(src)
        }
    }

    // MARK: - Réception d'état

    private func handleNotification(_ info: [AnyHashable: Any], from src: MediaSource) {
        let state = (info["Player State"] as? String) ?? ""
        if state == "Stopped" {
            if source == src || source == nil { clear() }
            return
        }
        let playing = state == "Playing"
        // Ne pas écraser une autre source qui est en train de jouer.
        if let current = source, current != src, isPlaying, !playing { return }

        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let durationKey = src == .spotify ? "Duration" : "Total Time"
        let durationMs = (info[durationKey] as? NSNumber)?.doubleValue ?? 0
        let newTrack = Track(
            id: "\(src.rawValue)|\(title)|\(artist)|\(album)",
            title: title, artist: artist, album: album,
            duration: durationMs / 1000
        )
        apply(source: src, track: newTrack, playing: playing)

        if let pos = (info["Playback Position"] as? NSNumber)?.doubleValue {
            setPosition(pos)
        } else {
            fetchState(src)
        }
    }

    private func apply(source src: MediaSource, track newTrack: Track, playing: Bool) {
        source = src
        if track != newTrack { track = newTrack }
        if isPlaying != playing { isPlaying = playing }
        if artworkKey != newTrack.id {
            artworkKey = newTrack.id
            fetchArtwork(src, key: newTrack.id)
        }
    }

    private func clear() {
        track = nil
        isPlaying = false
        source = nil
        artwork = nil
        artworkKey = nil
        accentColor = .white
    }

    private func periodicSync() {
        if let src = source {
            if isPlaying { fetchState(src) }
        } else {
            refreshFromRunningApps()
        }
    }

    private func refreshFromRunningApps() {
        for src in [MediaSource.spotify, .music] where src.isRunning {
            fetchState(src)
        }
    }

    /// Interroge l'app via AppleScript. Les nombres sont renvoyés en millisecondes entières
    /// pour éviter les problèmes de séparateur décimal selon la langue du système.
    private func fetchState(_ src: MediaSource) {
        guard src.isRunning else { return }
        run(Self.stateScript(for: src)) { [weak self] result in
            guard let self, let text = result?.stringValue else { return }
            if text == "stopped" {
                if self.source == src { self.clear() }
                return
            }
            let parts = text.components(separatedBy: "||")
            guard parts.count >= 6 else { return }
            let playing = parts[0] == "playing"
            if let current = self.source, current != src, self.isPlaying, !playing { return }
            let t = Track(
                id: "\(src.rawValue)|\(parts[1])|\(parts[2])|\(parts[3])",
                title: parts[1], artist: parts[2], album: parts[3],
                duration: (Double(parts[4]) ?? 0) / 1000
            )
            self.apply(source: src, track: t, playing: playing)
            self.setPosition((Double(parts[5]) ?? 0) / 1000)
        }
    }

    private static func stateScript(for src: MediaSource) -> String {
        let duration = src == .spotify
            ? "((duration of t) as string)"
            : "((round ((duration of t) * 1000)) as string)"
        return """
        try
            tell application "\(src.appName)"
                if player state is stopped then return "stopped"
                set t to current track
                return (player state as string) & "||" & (name of t) & "||" & (artist of t) & "||" & (album of t) & "||" & \(duration) & "||" & ((round ((player position) * 1000)) as string)
            end tell
        on error
            return "error"
        end try
        """
    }

    // MARK: - Pochette

    private func fetchArtwork(_ src: MediaSource, key: String) {
        switch src {
        case .spotify:
            run("tell application \"Spotify\" to return artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                Task { [weak self] in
                    guard let response = try? await URLSession.shared.data(from: url),
                          let image = NSImage(data: response.0) else { return }
                    self?.setArtwork(image, key: key)
                }
            }
        case .music:
            run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let data = result?.data, let image = NSImage(data: data) else {
                    self?.setArtwork(nil, key: key)
                    return
                }
                self?.setArtwork(image, key: key)
            }
        }
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard artworkKey == key else { return }
        artwork = image
        accentColor = Color(nsColor: image?.accentColor ?? .white)
    }

    // MARK: - AppleScript

    private func run(_ source: String, completion: @escaping @MainActor (NSAppleEventDescriptor?) -> Void) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            Task { @MainActor in completion(result) }
        }
    }
}
