import AppKit
import SwiftUI

enum MediaSource: String, CaseIterable {
    case spotify, music, safari, chrome, brave, edge

    static let native: [MediaSource] = [.spotify, .music]
    static let browsers: [MediaSource] = [.safari, .chrome, .brave, .edge]

    var isBrowser: Bool { Self.browsers.contains(self) }

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    /// Nom AppleScript de l'application
    var appName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .brave: "Brave Browser"
        case .edge: "Microsoft Edge"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Musique"
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        }
    }

    var notificationName: String? {
        switch self {
        case .spotify: "com.spotify.client.PlaybackStateChanged"
        case .music: "com.apple.Music.playerInfo"
        default: nil
        }
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

/// Lit et pilote Spotify / Apple Music (notifications + AppleScript) et les lecteurs
/// web (YouTube, Deezer, SoundCloud…) de Safari, Chrome, Brave et Edge (JavaScript via AppleScript).
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
    private var browserArtworkURL: URL?
    private var browserPollInFlight = false

    private init() {
        let center = DistributedNotificationCenter.default()
        for src in MediaSource.native {
            guard let name = src.notificationName else { continue }
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
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

    /// `measuredAt` : instant où la position a été lue (et non reçue), pour ne pas
    /// accumuler le délai d'AppleScript — indispensable pour des paroles bien synchronisées.
    private func setPosition(_ value: Double, measuredAt date: Date = Date()) {
        position = value
        positionDate = date
    }

    /// Milieu de l'aller-retour AppleScript : meilleure estimation de l'instant de lecture.
    private static func midpoint(since start: Date) -> Date {
        start.addingTimeInterval(Date().timeIntervalSince(start) / 2)
    }

    // MARK: - Commandes

    func playPause() {
        let current = currentPosition(at: Date())
        if let src = source, src.isBrowser {
            sendBrowser(src, action: "if(m.paused){m.play()}else{m.pause()};")
        } else {
            send("playpause")
        }
        isPlaying.toggle()
        setPosition(current)
    }

    func next() {
        if let src = source, src.isBrowser {
            sendBrowser(src, action: "var b=document.querySelector('.ytp-next-button,ytmusic-player-bar .next-button,[data-testid=control-button-skip-forward],.skipControl__next,[data-testid=next-button],[aria-label=Next],[aria-label=Suivant]');if(b){b.click()}else{m.currentTime=m.duration};")
        } else {
            send("next track")
        }
    }

    func previous() {
        if let src = source, src.isBrowser {
            sendBrowser(src, action: "var b=document.querySelector('.ytp-prev-button,ytmusic-player-bar .previous-button,[data-testid=control-button-skip-back],.skipControl__previous,[data-testid=previous-button],[aria-label=Previous],[aria-label=Précédent]');if(b&&m.currentTime<3){b.click()}else{m.currentTime=0};")
        } else {
            send("previous track")
        }
    }

    func seek(to seconds: Double) {
        if let src = source, src.isBrowser {
            sendBrowser(src, action: "m.currentTime=\(Int(seconds));")
        } else {
            send("set player position to \(Int(seconds))")
        }
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
        guard let src = source ?? MediaSource.native.first(where: { $0.isRunning }) else { return }
        run("tell application \"\(src.appName)\" to \(command)") { [weak self] _ in
            self?.fetchState(src)
        }
    }

    // MARK: - Réception d'état (Spotify / Musique)

    private func handleNotification(_ info: [AnyHashable: Any], from src: MediaSource) {
        let state = (info["Player State"] as? String) ?? ""
        if state == "Stopped" {
            if source == src || source == nil { clear() }
            return
        }
        let playing = state == "Playing"
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
        browserArtworkURL = nil
        accentColor = .white
    }

    private func periodicSync() {
        let browsersEnabled = AppSettings.shared.browserMedia
        if let src = source, !src.isBrowser {
            if isPlaying { fetchState(src) } else if browsersEnabled { pollBrowsers() }
        } else if source == nil {
            refreshFromRunningApps()
            if browsersEnabled { pollBrowsers() }
        } else if browsersEnabled {
            pollBrowsers()
        } else {
            clear()
        }
    }

    private func refreshFromRunningApps() {
        for src in MediaSource.native where src.isRunning {
            fetchState(src)
        }
    }

    /// Les nombres sont renvoyés en millisecondes entières pour éviter les problèmes
    /// de séparateur décimal selon la langue du système.
    private func fetchState(_ src: MediaSource) {
        guard src.isRunning, !src.isBrowser else { return }
        let requestedAt = Date()
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
            self.setPosition((Double(parts[5]) ?? 0) / 1000, measuredAt: Self.midpoint(since: requestedAt))
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

    // MARK: - Lecteurs web (navigateurs)

    /// Trouve l'élément <video>/<audio> qui joue (ou a déjà joué) dans la page.
    private static let mediaFinder = "var ms=Array.prototype.slice.call(document.querySelectorAll('video,audio'));var m=ms.find(function(e){return !e.paused&&e.duration>0})||ms.find(function(e){return e.duration>0&&e.currentTime>0});"

    private static let browserInfoJS = "(function(){" + mediaFinder +
        "if(!m){return ''}var md=navigator.mediaSession?navigator.mediaSession.metadata:null;var art='';" +
        "if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src}" +
        "return JSON.stringify({t:(md&&md.title)||document.title,a:(md&&md.artist)||location.hostname,al:(md&&md.album)||'',art:art,p:!m.paused,d:isFinite(m.duration)?m.duration:0,c:m.currentTime})})()"

    private static func browserActionJS(_ action: String) -> String {
        "(function(){" + mediaFinder + "if(!m){return ''}" + action + "return 'ok'})()"
    }

    private static let mediaDomains = [
        "youtube.com", "deezer.com", "soundcloud.com", "open.spotify.com", "music.apple.com",
        "twitch.tv", "vimeo.com", "bandcamp.com", "tidal.com", "qobuz.com", "mixcloud.com", "radiofrance.fr",
    ]

    private static func browserScript(_ src: MediaSource, js: String) -> String {
        let condition = mediaDomains.map { "u contains \"\($0)\"" }.joined(separator: " or ")
        let exec = src == .safari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        return """
        try
            tell application "\(src.appName)"
                repeat with w in windows
                    repeat with t in tabs of w
                        set u to URL of t
                        if u is not missing value and (\(condition)) then
                            set r to \(exec)
                            if r is not missing value and r is not "" then return r
                        end if
                    end repeat
                end repeat
            end tell
        end try
        return ""
        """
    }

    private func pollBrowsers() {
        guard AppSettings.shared.browserMedia, !browserPollInFlight else { return }
        let running = MediaSource.browsers.filter(\.isRunning)
        guard !running.isEmpty else {
            if source?.isBrowser == true { clear() }
            return
        }
        browserPollInFlight = true
        pollBrowser(in: running, at: 0)
    }

    private func pollBrowser(in list: [MediaSource], at index: Int) {
        guard index < list.count else {
            browserPollInFlight = false
            if source?.isBrowser == true { clear() }   // plus aucun lecteur web
            return
        }
        let src = list[index]
        let requestedAt = Date()
        run(Self.browserScript(src, js: Self.browserInfoJS)) { [weak self] result in
            guard let self else { return }
            if let text = result?.stringValue, !text.isEmpty,
               self.handleBrowserResult(text, from: src, measuredAt: Self.midpoint(since: requestedAt)) {
                self.browserPollInFlight = false
            } else {
                self.pollBrowser(in: list, at: index + 1)
            }
        }
    }

    private func handleBrowserResult(_ text: String, from src: MediaSource, measuredAt: Date) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = object["t"] as? String else { return false }
        // Une source native qui joue garde la priorité.
        if let current = source, !current.isBrowser, isPlaying { return true }

        let artist = object["a"] as? String ?? ""
        let album = object["al"] as? String ?? ""
        let playing = object["p"] as? Bool ?? false
        let duration = (object["d"] as? NSNumber)?.doubleValue ?? 0
        let position = (object["c"] as? NSNumber)?.doubleValue ?? 0
        browserArtworkURL = (object["art"] as? String).flatMap { URL(string: $0) }

        let newTrack = Track(id: "\(src.rawValue)|\(title)|\(artist)", title: title, artist: artist, album: album, duration: duration)
        apply(source: src, track: newTrack, playing: playing)
        setPosition(position, measuredAt: measuredAt)
        return true
    }

    private func sendBrowser(_ src: MediaSource, action: String) {
        run(Self.browserScript(src, js: Self.browserActionJS(action))) { [weak self] _ in
            self?.browserPollInFlight = false
            self?.pollBrowsers()
        }
    }

    // MARK: - Pochette

    private func fetchArtwork(_ src: MediaSource, key: String) {
        switch src {
        case .spotify:
            run("tell application \"Spotify\" to return artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                self?.downloadArtwork(url, key: key)
            }
        case .music:
            run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let data = result?.data, let image = NSImage(data: data) else {
                    self?.setArtwork(nil, key: key)
                    return
                }
                self?.setArtwork(image, key: key)
            }
        default:
            if let url = browserArtworkURL {
                downloadArtwork(url, key: key)
            } else {
                setArtwork(nil, key: key)
            }
        }
    }

    private func downloadArtwork(_ url: URL, key: String) {
        Task { [weak self] in
            guard let response = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: response.0) else { return }
            self?.setArtwork(image, key: key)
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
