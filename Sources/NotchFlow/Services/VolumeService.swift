import Foundation
import Combine
import CoreAudio
import AudioToolbox

/// Observe le volume de la sortie audio par défaut pour afficher un HUD dans le notch.
@MainActor
final class VolumeService: ObservableObject {
    static let shared = VolumeService()

    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    let changes = PassthroughSubject<Void, Never>()

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var observedDevices = Set<AudioObjectID>()

    private init() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateDefaultDevice() }
        }
        updateDefaultDevice()
    }

    private func updateDefaultDevice() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return }
        deviceID = id
        observe(id)
        read(notify: false)
    }

    private func observe(_ id: AudioObjectID) {
        guard !observedDevices.contains(id) else { return }
        observedDevices.insert(id)

        let properties: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in properties {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, self.deviceID == id else { return }
                    self.read(notify: true)
                }
            }
        }
    }

    private func read(notify: Bool) {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var ok = false
        if AudioHardwareServiceHasProperty(deviceID, &address) {
            ok = AudioHardwareServiceGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
        }
        if !ok {
            // Repli : moyenne des canaux gauche / droite
            let channels = [scalar(element: 1), scalar(element: 2)].compactMap { $0 }
            value = channels.isEmpty ? (scalar(element: kAudioObjectPropertyElementMain) ?? 0) : channels.reduce(0, +) / Float32(channels.count)
        }

        var muted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddress) {
            AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)
        }

        let newMuted = muted != 0
        let changed = abs(value - volume) > 0.001 || newMuted != isMuted
        volume = value
        isMuted = newMuted
        if notify && changed { changes.send() }
    }

    // MARK: - Réglage

    func setVolume(_ newValue: Float) {
        var value = Float32(min(max(newValue, 0), 1))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioHardwareServiceHasProperty(deviceID, &address) {
            AudioHardwareServiceSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        } else {
            for element in [kAudioObjectPropertyElementMain, 1, 2] as [AudioObjectPropertyElement] {
                var channel = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                if AudioObjectHasProperty(deviceID, &channel) {
                    AudioObjectSetPropertyData(deviceID, &channel, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
                }
            }
        }
        if value > 0 && isMuted { setMuted(false) }
        read(notify: true)
    }

    func setMuted(_ muted: Bool) {
        var flag: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(deviceID, &address) {
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &flag)
        }
        read(notify: true)
    }

    func toggleMute() { setMuted(!isMuted) }

    /// Pas de 1/16 (comme macOS), 1/64 avec ⌥⇧.
    func step(by delta: Float) {
        if isMuted && delta > 0 { setMuted(false) }
        setVolume(volume + delta)
    }

    private func scalar(element: AudioObjectPropertyElement) -> Float32? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
