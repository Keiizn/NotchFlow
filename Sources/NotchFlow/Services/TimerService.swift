import AppKit
import Combine

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    @Published private(set) var now = Date()

    let finished = PassthroughSubject<Void, Never>()
    private var ticker: Timer?

    var isRunning: Bool { endDate != nil }
    var isActive: Bool { endDate != nil || pausedRemaining != nil }

    var remaining: TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? 0
    }

    var progress: Double { total > 0 ? min(1, max(0, 1 - remaining / total)) : 0 }

    var remainingString: String { Format.clock(remaining.rounded(.up)) }

    private init() {}

    func start(minutes: Double) {
        total = minutes * 60
        now = Date()
        endDate = now.addingTimeInterval(total)
        pausedRemaining = nil
        startTicker()
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        stopTicker()
    }

    func resume() {
        guard let remaining = pausedRemaining else { return }
        now = Date()
        endDate = now.addingTimeInterval(remaining)
        pausedRemaining = nil
        startTicker()
    }

    func add(minutes: Double) {
        let extra = minutes * 60
        total += extra
        if let endDate { self.endDate = endDate.addingTimeInterval(extra) }
        else if let pausedRemaining { self.pausedRemaining = pausedRemaining + extra }
    }

    func stop() {
        endDate = nil
        pausedRemaining = nil
        total = 0
        stopTicker()
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        now = Date()
        if let endDate, endDate <= now {
            stop()
            NSSound(named: "Glass")?.play()
            finished.send()
        }
    }
}
