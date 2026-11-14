import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

/// Paroles synchronisées via LRCLIB (gratuit, sans clé : https://lrclib.net).
///
/// Chaque résultat est vérifié (titre, artiste et surtout durée) : on préfère
/// « paroles introuvables » à des paroles d'une autre chanson ou d'une autre version.
@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    enum State: Equatable { case idle, loading, synced, plain, notFound }

    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: String = ""
    @Published private(set) var state: State = .idle
    /// Décalage manuel (secondes) : positif = paroles plus tôt.
    @Published var offset: Double = 0

    private var currentKey: String?
    private var cache: [String: (lines: [LyricLine], plain: String)] = [:]

    /// Champs renvoyés par /api/get et /api/search.
    private struct Candidate: Decodable {
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    /// Une interprétation possible du morceau (titre / artiste) à chercher.
    private struct Query {
        let title: String
        let artist: String
        let album: String
        let duration: Double
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
        let key = track.id
        guard key != currentKey else { return }
        currentKey = key
        offset = 0

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
        let t = position + offset + 0.15
        var low = 0, high = lines.count - 1, result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= t {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func nudge(_ delta: Double) {
        offset = (offset + delta).clamped(to: -10...10)
    }

    private func apply(_ newLines: [LyricLine], _ plain: String) {
        lines = newLines
        plainText = plain
        state = !newLines.isEmpty ? .synced : (plain.isEmpty ? .notFound : .plain)
    }

    // MARK: - Recherche

    private static func fetch(_ track: Track) async -> (lines: [LyricLine], plain: String) {
        for query in queries(for: track) {
            if let best = await bestCandidate(for: query) {
                return (parse(best.syncedLyrics ?? ""), best.plainLyrics ?? "")
            }
        }
        return ([], "")
    }

    /// Interprétations du morceau, de la plus fiable à la moins fiable.
    private static func queries(for track: Track) -> [Query] {
        let title = cleanTitle(track.title)
        let artist = primaryArtist(track.artist)
        var result = [Query(title: title, artist: artist, album: track.album, duration: track.duration)]

        // Vidéos YouTube & co : « Artiste - Titre (Clip officiel) »
        if let range = track.title.range(of: " - ") ?? track.title.range(of: " – ") {
            let left = String(track.title[..<range.lowerBound])
            let right = String(track.title[range.upperBound...])
            result.append(Query(title: cleanTitle(right), artist: primaryArtist(left), album: "", duration: track.duration))
        }
        return result
    }

    private static func bestCandidate(for query: Query) async -> Candidate? {
        guard !query.title.isEmpty else { return nil }

        // 1. Correspondance exacte (LRCLIB filtre déjà la durée à ±2 s)
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if !query.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: query.album)) }
        if query.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(query.duration.rounded())))) }
        get.queryItems = items
        if let exact: Candidate = await request(get.url!), score(exact, for: query) != nil {
            return exact
        }

        // 2. Recherche, puis choix du meilleur résultat VÉRIFIÉ
        var candidates: [Candidate] = []
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: query.title),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        if let found: [Candidate] = await request(search.url!) { candidates += found }

        if candidates.isEmpty {
            var loose = URLComponents(string: "https://lrclib.net/api/search")!
            loose.queryItems = [URLQueryItem(name: "q", value: "\(query.artist) \(query.title)")]
            if let found: [Candidate] = await request(loose.url!) { candidates += found }
        }

        return candidates
            .compactMap { candidate in score(candidate, for: query).map { (candidate, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Note de confiance, ou `nil` si le résultat ne correspond pas au morceau.
    private static func score(_ c: Candidate, for q: Query) -> Double? {
        guard c.syncedLyrics?.isEmpty == false || c.plainLyrics?.isEmpty == false else { return nil }
        if c.instrumental == true { return nil }

        let candidateTitle = normalize(cleanTitle(c.trackName ?? ""))
        let wantedTitle = normalize(q.title)
        guard !candidateTitle.isEmpty, !wantedTitle.isEmpty else { return nil }

        var points = 0.0
        if candidateTitle == wantedTitle {
            points += 4
        } else if candidateTitle.contains(wantedTitle) || wantedTitle.contains(candidateTitle) {
            points += 2
        } else {
            return nil
        }

        let candidateArtist = normalize(c.artistName ?? "")
        let wantedArtist = normalize(q.artist)
        if !wantedArtist.isEmpty {
            if candidateArtist == wantedArtist {
                points += 3
            } else if candidateArtist.contains(wantedArtist) || wantedArtist.contains(candidateArtist)
                        || !words(candidateArtist).isDisjoint(with: words(wantedArtist)) {
                points += 1.5
            } else {
                return nil
            }
        }

        // La durée garantit la bonne VERSION (radio edit, live, remix…) et donc la synchro.
        if q.duration > 0, let duration = c.duration, duration > 0 {
            let gap = abs(duration - q.duration)
            guard gap <= 4 else { return nil }
            points += 3 - gap * 0.5
        }

        if c.syncedLyrics?.isEmpty == false { points += 2 }
        return points
    }

    // MARK: - Nettoyage du texte

    /// « Titre (feat. X) [Remastered 2011] - Radio Edit » → « Titre »
    private static func cleanTitle(_ title: String) -> String {
        var t = title
        t = t.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        for separator in [" - ", " – ", " | "] {
            if let range = t.range(of: separator) {
                let tail = t[range.upperBound...].lowercased()
                let noise = ["remaster", "live", "version", "edit", "mix", "mono", "stereo", "official", "clip", "audio", "lyrics", "paroles"]
                if noise.contains(where: { tail.contains($0) }) { t = String(t[..<range.lowerBound]) }
            }
        }
        t = t.replacingOccurrences(of: #"\s+(feat\.?|ft\.?|featuring)\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// « Artiste A, Artiste B & C » → « Artiste A » ; retire « VEVO », « - Topic ».
    private static func primaryArtist(_ artist: String) -> String {
        var a = artist
        a = a.replacingOccurrences(of: #"(?i)vevo$|\s-\s*topic$|\s+official$"#, with: "", options: .regularExpression)
        for separator in [", ", " & ", " feat", " ft.", " x ", " et "] {
            if let range = a.range(of: separator, options: .caseInsensitive) {
                a = String(a[..<range.lowerBound])
            }
        }
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Minuscules, sans accents ni ponctuation, espaces simples.
    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(separator: " ").map(String.init).filter { $0.count >= 3 })
    }

    // MARK: - Réseau

    private static func request<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("NotchFlow (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: result.0)
    }

    /// « [01:23.45] texte » → (83.45, « texte »). Gère plusieurs horodatages par ligne.
    private static func parse(_ lrc: String) -> [LyricLine] {
        guard let stamp = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#) else { return [] }
        var entries: [(Double, String)] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            let matches = stamp.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let last = matches.last, let textStart = Range(last.range, in: line)?.upperBound else { continue }
            let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let m = Range(match.range(at: 1), in: line), let s = Range(match.range(at: 2), in: line) else { continue }
                let seconds = Double(line[s].replacingOccurrences(of: ":", with: ".")) ?? 0
                entries.append(((Double(line[m]) ?? 0) * 60 + seconds, text.isEmpty ? "♪" : text))
            }
        }
        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
