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
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Oreille gauche
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        p.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        // Coin bas gauche
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        // Coin bas droit
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Oreille droite
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
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

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .notch:
            content
                .background(Color.black)
                .clipShape(NotchShape(topRadius: earRadius, bottomRadius: bottomRadius))
        case .island:
            content
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: isOpen ? 32 : height / 2, style: .continuous))
        }
    }
}
