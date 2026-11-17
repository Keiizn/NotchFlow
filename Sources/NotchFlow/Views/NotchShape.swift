import SwiftUI

/// Forme du notch : petites « oreilles » concaves en haut qui se fondent dans
/// le bord de l'écran, coins arrondis en bas. Les deux rayons sont animables.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, (rect.width - 2 * top) / 2, rect.height - top)
        // Coins « continus » (squircle) : la courbure varie progressivement
        // au lieu de casser net comme un arc de cercle.
        let k: CGFloat = 0.62
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Oreille gauche
        p.addCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control1: CGPoint(x: rect.minX + top * k, y: rect.minY),
            control2: CGPoint(x: rect.minX + top, y: rect.minY + top * (1 - k))
        )
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Coin bas gauche
        p.addCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control1: CGPoint(x: rect.minX + top, y: rect.maxY - bottom * (1 - k)),
            control2: CGPoint(x: rect.minX + top + bottom * (1 - k), y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Coin bas droit
        p.addCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control1: CGPoint(x: rect.maxX - top - bottom * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom * (1 - k))
        )
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Oreille droite
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - top, y: rect.minY + top * (1 - k)),
            control2: CGPoint(x: rect.maxX - top * k, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// Fond noir découpé en notch ou en « Dynamic Island ».
struct NotchBackground: ViewModifier {
    let style: AppSettings.Style
    let isOpen: Bool
    let earRadius: CGFloat
    let bottomRadius: CGFloat
    let height: CGFloat
    var notchHeight: CGFloat = 32
    var glass: Bool = false
    var glassTint: Double = 0.3

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .notch:
            decorate(content, shape: NotchShape(topRadius: earRadius, bottomRadius: bottomRadius))
        case .island:
            decorate(content, shape: RoundedRectangle(cornerRadius: isOpen ? 32 : height / 2, style: .continuous))
        }
    }

    /// Verre : liseré franc. Noir : lueur à peine visible sur le bord bas (notch ouvert, île).
    private func rimOpacity(_ glassOn: Bool) -> Double {
        if glassOn { return 1 }
        if isOpen { return 0.35 }
        return style == .island ? 0.4 : 0
    }

    private func decorate<S: Shape>(_ content: Content, shape: S) -> some View {
        let glassOn = glass && isOpen
        return content
            .background {
                NotchSurface(glass: glassOn, tint: glassTint, notchHeight: notchHeight)
            }
            .clipShape(shape)
            .overlay {
                // Liseré lumineux du verre (plus marqué en bas, là où la lumière « accroche »)
                shape
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.18), .white.opacity(0.35)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .opacity(rimOpacity(glassOn))
                    .allowsHitTesting(false)
            }
    }
}
