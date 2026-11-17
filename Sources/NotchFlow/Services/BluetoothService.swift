import Foundation
import IOBluetooth
import Combine

/// Connexion / déconnexion des appareils Bluetooth (AirPods, casques, claviers…)
/// avec leur niveau de batterie quand macOS le connaît.
@MainActor
final class BluetoothService: NSObject {
    static let shared = BluetoothService()

    struct Event: Equatable {
        let name: String
        let icon: String
        let battery: Int?
        let connected: Bool
    }

    let events = PassthroughSubject<Event, Never>()

    private var connectNotification: IOBluetoothUserNotification?
    private var startedAt = Date()
    /// Dernière annonce par appareil, et heure de connexion (anti-clignotement).
    private var lastAnnounced: [String: (connected: Bool, date: Date)] = [:]
    private var connectedSince: [String: Date] = [:]

    private override init() { super.init() }

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        // Appelé aussi pour les appareils déjà connectés au lancement (ignorés, voir `handle`).
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        guard let device else { return }
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        let info = Self.describe(device)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handle(info, connected: true) }
        }
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification?, device: IOBluetoothDevice?) {
        notification?.unregister()
        guard let device else { return }
        let info = Self.describe(device)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.handle(info, connected: false) }
        }
    }

    private struct Info: Sendable {
        let name: String
        let icon: String
        /// Appareil reconnu (écouteurs, clavier, souris, manette…). Les autres — montre,
        /// iPhone en Continuity, objets connectés — se reconnectent sans cesse en arrière-plan.
        var known: Bool { icon != Self.genericIcon }
        static let genericIcon = "dot.radiowaves.left.and.right"
    }

    private func handle(_ info: Info, connected: Bool) {
        let now = Date()
        if connected {
            connectedSince[info.name] = now
        }
        // Les appareils déjà connectés au démarrage ne déclenchent pas d'animation.
        guard now.timeIntervalSince(startedAt) > 4, info.known else { return }
        if !connected {
            // Déconnexion juste après une connexion : simple reconnexion automatique.
            if let since = connectedSince.removeValue(forKey: info.name), now.timeIntervalSince(since) < 30 { return }
        }
        // Même annonce pour le même appareil il y a moins de 10 min : on se tait.
        if let last = lastAnnounced[info.name], last.connected == connected, now.timeIntervalSince(last.date) < 600 { return }
        lastAnnounced[info.name] = (connected, now)
        events.send(Event(name: info.name, icon: info.icon, battery: nil, connected: connected))
        guard connected else { return }
        // La batterie n'est connue de macOS qu'une ou deux secondes après la connexion.
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if let level = await Self.batteryLevel(named: info.name) {
                self.events.send(Event(name: info.name, icon: info.icon, battery: level, connected: true))
            }
        }
    }

    // MARK: - Description

    nonisolated private static func describe(_ device: IOBluetoothDevice) -> Info {
        let name = device.name ?? device.nameOrAddress ?? "Appareil Bluetooth"
        return Info(name: name, icon: icon(name: name, major: UInt32(device.deviceClassMajor), minor: UInt32(device.deviceClassMinor)))
    }

    nonisolated static func icon(name: String, major: UInt32, minor: UInt32) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        if n.contains("keyboard") || n.contains("clavier") { return "keyboard" }
        if n.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if n.contains("mouse") || n.contains("souris") { return "magicmouse.fill" }
        switch major {
        case 0x02: return "iphone"                       // téléphone
        case 0x04: return "headphones"                   // audio / vidéo
        case 0x05:                                       // périphérique
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse.fill" }
            return "gamecontroller.fill"
        default: return Info.genericIcon
        }
    }

    // MARK: - Batterie

    /// Niveau lu dans `system_profiler` (le plus faible des écouteurs pour les AirPods).
    nonisolated static func batteryLevel(named name: String) async -> Int? {
        let output = await QuickActions.output("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }

        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                guard let props = entry[name] as? [String: Any] else { continue }
                let keys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelMain", "device_batteryLevel"]
                let levels = keys.compactMap { key -> Int? in
                    guard let text = props[key] as? String else { return nil }
                    return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
                }
                return levels.min()
            }
        }
        return nil
    }
}
