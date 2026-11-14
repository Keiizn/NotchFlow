import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

/// Paroles synchronisées via LRCLIB (gratuit, sans clé : https://lrclib.net).
@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    enum State: Equatable { case idle, loading, synced, plain, notFound }

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: String = ""
    @Published private(set) var state: State = .idle

    private var currentKey: String?
    private var cache: [String: (lines: [LyricLine], plain: String)] = [:]

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private init() {}

    func load(for track: Track?) {
        guard AppSettings.shared.showLyrics, let track, !track.title.isEmpty else {
            currentKey = nil
            lines = []
            plainText = ""
            state = .idle
            return
        }
        let key = "\(track.artist)|\(track.title)"
        guard key != currentKey else { return }
        currentKey = key

        if let cached = cache[key] {
            apply(cached.lines, cached.plain)
            return
        }
        lines = []
        plainText = ""
        state = .loading
        Task {
            let result = await Self.fetch(track)
            guard currentKey == key else { return }
            cache[key] = result
            apply(result.lines, result.plain)
        }
    }

    /// Index de la ligne en cours à la position donnée (secondes).
    func index(at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var result: Int?
        for line in lines where line.time <= position + 0.25 {
            result = line.id
        }
        return result
    }

    private func apply(_ newLines: [LyricLine], _ plain: String) {
        lines = newLines
        plainText = plain
        state = !newLines.isEmpty ? .synced : (plain.isEmpty ? .notFound : .plain)
    }

    // MARK: - Réseau

    private static func fetch(_ track: Track) async -> (lines: [LyricLine], plain: String) {
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "track_name", value: track.title),
        ]
        if !track.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        get.queryItems = items

        if let response: Response = await request(get.url!), response.syncedLyrics != nil || response.plainLyrics != nil {
            return (parse(response.syncedLyrics ?? ""), response.plainLyrics ?? "")
        }

        // Repli : recherche plus souple
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if let results: [Response] = await request(search.url!),
           let best = results.first(where: { $0.syncedLyrics != nil }) ?? results.first {
            return (parse(best.syncedLyrics ?? ""), best.plainLyrics ?? "")
        }
        return ([], "")
    }

    private static func request<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("NotchFlow (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: result.0)
    }

    /// « [01:23.45] texte » → (83.45, « texte »)
    private static func parse(_ lrc: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$"#) else { return [] }
        var result: [LyricLine] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let minutesRange = Range(match.range(at: 1), in: line),
                  let secondsRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 3), in: line) else { continue }
            let time = (Double(line[minutesRange]) ?? 0) * 60 + (Double(line[secondsRange]) ?? 0)
            let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
            result.append(LyricLine(id: result.count, time: time, text: text.isEmpty ? "♪" : text))
        }
        return result
    }
}
