import AppKit
import SwiftUI

enum Format {
    /// 125 → « 2:05 », 3725 → « 1:02:05 »
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension NSImage {
    /// Couleurs moyennes des moitiés gauche et droite, ravivées (effet Ambilight).
    var edgeColors: [NSColor]? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 8)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 2, height: 1,
                bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 2, height: 1))
            return true
        }
        guard drawn else { return nil }
        return [0, 4].map { i in
            let base = NSColor(srgbRed: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                               blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return NSColor(hue: h, saturation: min(s * 1.4, 1), brightness: max(b, 0.8), alpha: 1)
        }
    }

    /// Couleur moyenne de l'image, ravivée pour servir de couleur d'accent.
    var accentColor: NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let base = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(s * 1.25, 1), brightness: max(b, 0.75), alpha: 1)
    }
}
