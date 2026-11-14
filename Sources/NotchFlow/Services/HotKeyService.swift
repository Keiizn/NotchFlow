import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global ⌥⌘N pour ouvrir / fermer le notch
/// (API Carbon : aucune autorisation nécessaire).
@MainActor
final class HotKeyService {
    static let shared = HotKeyService()

    static let displayString = "⌥⌘N"
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register() {
        unregister()
        guard AppSettings.shared.hotKeyEnabled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(noErr) }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { service.onPress?() }
            return OSStatus(noErr)
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E46_4C57), id: 1) // « NFLW »
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
