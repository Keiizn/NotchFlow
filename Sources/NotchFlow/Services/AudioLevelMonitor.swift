import AudioToolbox
import CoreAudio
import Foundation
import os

/// Niveau sonore de la sortie du Mac, pour faire « respirer » le halo en rythme.
///
/// Utilise un « process tap » Core Audio (macOS 14.2+) : on écoute le son déjà joué,
/// sans micro. macOS demande l'autorisation « Enregistrement audio du système » la
/// première fois. Si elle est refusée ou indisponible, `isLive` reste faux et le halo
/// utilise une pulsation simulée.
final class AudioLevelMonitor: @unchecked Sendable {
    static let shared = AudioLevelMonitor()

    /// Niveau lissé 0…1 et impulsion de battement 0…1 (lus à chaque image).
    private let state = OSAllocatedUnfairLock(initialState: Levels())
    private struct Levels {
        var level: Float = 0
        var beat: Float = 0
        var average: Float = 0.02
        var updated = Date.distantPast
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "app.notchflow.audiolevel", qos: .userInteractive)
    private var users = 0
    private var failed = false

    /// Vrai si on reçoit du vrai son depuis moins d'une seconde.
    var isLive: Bool {
        state.withLock { Date().timeIntervalSince($0.updated) < 1 }
    }

    /// (niveau, battement) actuels, entre 0 et 1.
    func current() -> (level: Double, beat: Double) {
        state.withLock { s in
            // Retombe doucement si plus aucun buffer n'arrive.
            let stale = Date().timeIntervalSince(s.updated) > 0.3
            return stale ? (0, 0) : (Double(s.level), Double(s.beat))
        }
    }

    // MARK: - Démarrage / arrêt (compteur d'utilisateurs)

    func acquire() {
        queue.async { [self] in
            users += 1
            if users == 1 { start() }
        }
    }

    func release() {
        queue.async { [self] in
            users = max(users - 1, 0)
            if users == 0 { stop() }
        }
    }

    private func start() {
        guard !failed, procID == nil else { return }
        guard #available(macOS 14.2, *) else { failed = true; return }
        do {
            try createTap()
        } catch {
            NSLog("NotchFlow: capture audio indisponible (\(error))")
            stop()
            failed = true
        }
    }

    @available(macOS 14.2, *)
    private func createTap() throws {
        // 1. Tap stéréo global (tout le son du Mac, sans le couper).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "NotchFlow Halo"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "tap")
        tapID = tap

        // 2. Périphérique agrégé privé qui contient ce tap.
        let outputUID = try defaultOutputUID()
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NotchFlow Halo",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "agrégat")
        aggregateID = aggregate

        // 3. Lecture des buffers.
        var proc: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }, "ioproc")
        procID = proc
        try check(AudioDeviceStart(aggregate, proc), "start")
    }

    private func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = kAudioObjectUnknown
        tapID = kAudioObjectUnknown
    }

    // MARK: - Analyse

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var sum: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<n {
                let v = samples[i]
                sum += v * v
            }
            count += n
        }
        guard count > 0 else { return }
        let rms = (sum / Float(count)).squareRoot()

        state.withLock { s in
            // Moyenne lente : sert de référence pour normaliser et détecter les battements.
            s.average += (rms - s.average) * 0.02
            let reference = max(s.average * 2.2, 0.01)
            let target = min(rms / reference, 1)
            // Monte vite, redescend lentement (comme un vumètre).
            s.level += (target - s.level) * (target > s.level ? 0.6 : 0.12)
            // Battement : pic net au-dessus de la moyenne.
            if rms > s.average * 1.6 && rms > 0.01 {
                s.beat = 1
            } else {
                s.beat *= 0.86
            }
            s.updated = Date()
        }
    }

    // MARK: - Utilitaires Core Audio

    private struct AudioError: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step): \(status)" }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw AudioError(step: step, status: status) }
    }

    private func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "sortie")

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid), "uid")
        guard let value = uid?.takeRetainedValue() else { throw AudioError(step: "uid", status: -1) }
        return value as String
    }
}
