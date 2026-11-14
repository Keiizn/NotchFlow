import AppKit
import ApplicationServices

/// Intercepte les touches volume / luminosité du clavier pour remplacer les HUD
/// système par ceux du notch. Nécessite l'autorisation « Accessibilité ».
@MainActor
final class MediaKeyService: ObservableObject {
    static let shared = MediaKeyService()

    @Published private(set) var isActive = false
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustTimer: Timer?

    // Codes des touches spéciales (NX_KEYTYPE_*)
    private enum Key {
        static let soundUp = 0
        static let soundDown = 1
        static let brightnessUp = 2
        static let brightnessDown = 3
        static let mute = 7
    }

    private init() {}

    /// Démarre l'interception si le réglage est actif. Demande l'autorisation si besoin.
    func start() {
        guard AppSettings.shared.replaceSystemHUD else {
            stop()
            return
        }
        isTrusted = AXIsProcessTrusted()
        guard isTrusted else {
            waitForTrust()
            return
        }
        installTap()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        isActive = false
    }

    /// Ouvre la demande d'autorisation Accessibilité de macOS.
    func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted { waitForTrust() }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func waitForTrust() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.isTrusted = true
                    self.trustTimer?.invalidate()
                    self.trustTimer = nil
                    self.start()
                }
            }
        }
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<MediaKeyService>.fromOpaque(refcon).takeUnretainedValue()

            // macOS désactive le tap s'il est trop lent : on le réactive.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { service.reenable() }
                return Unmanaged.passUnretained(event)
            }
            guard type.rawValue == 14,
                  let nsEvent = NSEvent(cgEvent: event),
                  nsEvent.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            let data = nsEvent.data1
            let keyCode = (data & 0xFFFF_0000) >> 16
            let isDown = ((data & 0xFF00) >> 8) == 0xA
            let fine = nsEvent.modifierFlags.contains([.option, .shift])
            let handled = MainActor.assumeIsolated {
                service.handle(keyCode: keyCode, isDown: isDown, fine: fine)
            }
            return handled ? nil : Unmanaged.passUnretained(event)
        }

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        isActive = true
    }

    private func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Renvoie `true` si la touche est gérée (et donc retirée du flux système).
    private func handle(keyCode: Int, isDown: Bool, fine: Bool) -> Bool {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch keyCode {
        case Key.soundUp:
            if isDown { VolumeService.shared.step(by: step) }
            return true
        case Key.soundDown:
            if isDown { VolumeService.shared.step(by: -step) }
            return true
        case Key.mute:
            if isDown { VolumeService.shared.toggleMute() }
            return true
        case Key.brightnessUp, Key.brightnessDown:
            guard BrightnessService.shared.isAvailable else { return false }
            if isDown { BrightnessService.shared.step(by: keyCode == Key.brightnessUp ? step : -step) }
            return true
        default:
            return false
        }
    }
}
