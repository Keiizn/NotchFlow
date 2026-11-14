import Foundation

/// Chronomètre avec tours.
@MainActor
final class StopwatchService: ObservableObject {
    static let shared = StopwatchService()

    @Published private(set) var startDate: Date?
    @Published private(set) var accumulated: TimeInterval = 0
    @Published private(set) var laps: [TimeInterval] = []

    var isRunning: Bool { startDate != nil }
    var hasTime: Bool { isRunning || accumulated > 0 }

    private init() {}

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (startDate.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard startDate == nil else { return }
        startDate = Date()
    }

    func pause() {
        guard let startDate else { return }
        accumulated += Date().timeIntervalSince(startDate)
        self.startDate = nil
    }

    func lap() {
        guard isRunning else { return }
        laps.insert(elapsed(), at: 0)
        if laps.count > 20 { laps.removeLast() }
    }

    func reset() {
        startDate = nil
        accumulated = 0
        laps = []
    }

    /// 1:23,4 ou 1:02:03
    static func format(_ t: TimeInterval, tenths: Bool = true) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if !tenths { return String(format: "%d:%02d", m, s) }
        let d = Int((t - Double(total)) * 10)
        return String(format: "%d:%02d,%d", m, s, d)
    }
}
