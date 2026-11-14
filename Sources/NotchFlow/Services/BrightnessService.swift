import AppKit
import Combine
import CoreGraphics

/// Luminosité de l'écran intégré via le framework système DisplayServices
/// (chargé dynamiquement : aucune dépendance au moment de la compilation).
@MainActor
final class BrightnessService: ObservableObject {
    static let shared = BrightnessService()

    @Published private(set) var brightness: Float = 0.5
    let changes = PassthroughSubject<Void, Never>()

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private var getFunction: GetBrightness?
    private var setFunction: SetBrightness?

    var isAvailable: Bool { getFunction != nil && setFunction != nil }

    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) {
            if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
                getFunction = unsafeBitCast(symbol, to: GetBrightness.self)
            }
            if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
                setFunction = unsafeBitCast(symbol, to: SetBrightness.self)
            }
        }
        read()
    }

    /// Écran intégré du MacBook (sinon l'écran principal).
    private var displayID: CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        if CGGetOnlineDisplayList(16, &ids, &count) == .success {
            for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
                return id
            }
        }
        return CGMainDisplayID()
    }

    @discardableResult
    func read() -> Float {
        var value: Float = 0
        if let getFunction, getFunction(displayID, &value) == 0 {
            brightness = value
        }
        return brightness
    }

    func set(_ value: Float, notify: Bool = true) {
        let clamped = min(max(value, 0), 1)
        _ = setFunction?(displayID, clamped)
        brightness = clamped
        if notify { changes.send() }
    }

    func step(by delta: Float) {
        read()
        set(brightness + delta)
    }
}
