import Foundation
import Combine
import IOKit.ps

@MainActor
final class BatteryService: ObservableObject {
    static let shared = BatteryService()

    enum Event { case pluggedIn(Int), unplugged(Int) }

    @Published private(set) var level: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    @Published private(set) var minutesRemaining: Int?

    let events = PassthroughSubject<Event, Never>()
    private var runLoopSource: CFRunLoopSource?

    var symbolName: String {
        if isCharging || (isPluggedIn && level >= 100) { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private init() {
        refresh(initial: true)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.refresh(initial: false) }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    private func refresh(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description["Type"] as? String) == "InternalBattery"
            else { continue }

            let current = description["Current Capacity"] as? Int ?? 0
            let max = description["Max Capacity"] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let plugged = (description["Power Source State"] as? String) == "AC Power"
            let charging = description["Is Charging"] as? Bool ?? false
            let remaining = description["Time to Empty"] as? Int

            let wasPlugged = isPluggedIn
            hasBattery = true
            level = newLevel
            isCharging = charging
            isPluggedIn = plugged
            minutesRemaining = (remaining ?? -1) > 0 ? remaining : nil

            if !initial && plugged != wasPlugged {
                events.send(plugged ? .pluggedIn(newLevel) : .unplugged(newLevel))
            }
            return
        }
    }
}
