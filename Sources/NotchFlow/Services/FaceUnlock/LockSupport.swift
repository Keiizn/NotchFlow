import AppKit
import CoreGraphics

/// État réel de la session (les notifications servent seulement de déclencheurs).
enum LockState {
    private static var session: [String: Any] {
        (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
    }

    /// L'écran de la session courante est verrouillé.
    static var isLocked: Bool {
        (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    /// La session est celle affichée à l'écran (pas un changement rapide d'utilisateur).
    static var isOnConsole: Bool {
        (session["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue ?? true
    }
}

/// Saisie du mot de passe dans l'écran verrouillé (nécessite l'autorisation Accessibilité).
enum KeyTyper {
    static var isAllowed: Bool { AXIsProcessTrusted() }

    static func typeAndReturn(_ secret: Data) {
        guard isAllowed else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        // Vide le champ (⌘A puis ⌫) au cas où une touche aurait déjà été tapée.
        key(0x00, flags: .maskCommand, source: source)
        key(0x33, source: source)

        var units = Array(String(decoding: secret, as: UTF8.self).utf16)
        var index = 0
        while index < units.count {
            var end = min(index + 16, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
            var chunk = Array(units[index..<end])
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event?.post(tap: .cghidEventTap)
                usleep(4_000)
            }
            for i in chunk.indices { chunk[i] = 0 }
            index = end
        }
        for i in units.indices { units[i] = 0 }
        usleep(30_000)
        key(0x24, source: source) // Entrée
    }

    private static func key(_ code: CGKeyCode, flags: CGEventFlags = [], source: CGEventSource?) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            usleep(4_000)
        }
    }
}

/// Espace SkyLight au niveau de l'écran verrouillé : les fenêtres qu'on y place restent
/// visibles par-dessus la fenêtre de connexion. API privée chargée dynamiquement :
/// si elle manque, l'île n'est simplement pas affichée sur l'écran verrouillé.
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int, Int) -> Int32
    private typealias SetAbsoluteLevel = @convention(c) (Int32, Int, Int) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int, CFArray, Int) -> Int32
    private typealias RemoveWindows = @convention(c) (Int32, CFArray, CFArray) -> Int32

    private let connection: Int32
    private let space: Int
    private let addWindows: AddWindows
    private let removeWindows: RemoveWindows

    let isAvailable: Bool

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_NOW),
              let pMain = dlsym(handle, "SLSMainConnectionID"),
              let pCreate = dlsym(handle, "SLSSpaceCreate"),
              let pLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let pShow = dlsym(handle, "SLSShowSpaces"),
              let pAdd = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
              let pRemove = dlsym(handle, "SLSRemoveWindowsFromSpaces") else {
            connection = 0; space = 0
            addWindows = { _, _, _, _ in 0 }
            removeWindows = { _, _, _ in 0 }
            isAvailable = false
            return
        }
        let main = unsafeBitCast(pMain, to: MainConnection.self)
        let create = unsafeBitCast(pCreate, to: SpaceCreate.self)
        let setLevel = unsafeBitCast(pLevel, to: SetAbsoluteLevel.self)
        let show = unsafeBitCast(pShow, to: ShowSpaces.self)
        addWindows = unsafeBitCast(pAdd, to: AddWindows.self)
        removeWindows = unsafeBitCast(pRemove, to: RemoveWindows.self)

        connection = main()
        space = Int(create(connection, 1, 0))
        // 400 : niveau des notifications sur l'écran verrouillé.
        _ = setLevel(connection, space, 400)
        _ = show(connection, [NSNumber(value: space)] as CFArray)
        isAvailable = space != 0
    }

    func attach(_ window: NSWindow) {
        guard isAvailable else { return }
        _ = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }

    func detach(_ window: NSWindow) {
        guard isAvailable else { return }
        _ = removeWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: space)] as CFArray)
    }
}
