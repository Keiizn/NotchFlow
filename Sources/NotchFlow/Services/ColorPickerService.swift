import AppKit
import SwiftUI

/// Pipette : choisit une couleur n'importe où à l'écran et copie son code hexadécimal.
@MainActor
final class ColorPickerService: ObservableObject {
    static let shared = ColorPickerService()

    @Published private(set) var recent: [String] = []   // « #RRGGBB »
    @Published private(set) var lastCopied: String?

    private let key = "colorPicker.recent"
    private var sampler: NSColorSampler?

    private init() {
        recent = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Lance la loupe système. `completion` est appelé une fois la couleur choisie (ou annulée).
    func pick(completion: @escaping () -> Void = {}) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            let hex = color.flatMap { Self.hex($0) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let hex {
                        self?.add(hex)
                        self?.copy(hex)
                    }
                    self?.sampler = nil
                    completion()
                }
            }
        }
    }

    func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        lastCopied = hex
    }

    func clear() {
        recent = []
        UserDefaults.standard.set(recent, forKey: key)
    }

    private func add(_ hex: String) {
        recent.removeAll { $0 == hex }
        recent.insert(hex, at: 0)
        if recent.count > 8 { recent.removeLast(recent.count - 8) }
        UserDefaults.standard.set(recent, forKey: key)
    }

    nonisolated static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func color(_ hex: String) -> Color {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static func rgb(_ hex: String) -> String {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return "rgb(\((value >> 16) & 0xFF), \((value >> 8) & 0xFF), \(value & 0xFF))"
    }
}
