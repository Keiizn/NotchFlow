import SwiftUI

@MainActor
struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                        Image(systemName: "music.note")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Égaliseur animé affiché à côté du notch pendant la lecture.
@MainActor
struct AudioBars: View {
    var color: Color
    var isPlaying: Bool
    var count: Int = 4
    var height: CGFloat = 16
    var barWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.8) {
                ForEach(0..<count, id: \.self) { i in
                    let speed = 1.7 + Double((i * 7) % 5) * 0.45
                    let phase = t * speed + Double(i) * 1.3
                    let level = isPlaying ? 0.22 + 0.78 * abs(sin(phase) * cos(phase * 0.6 + Double(i))) : 0.18
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: barWidth, height: max(barWidth, height * level))
                }
            }
        }
        .frame(height: height)
    }
}

/// Curseur fin et déplaçable (HUD volume / luminosité, contrôles).
@MainActor
struct HUDSlider: View {
    var value: Double
    var color: Color = .white
    var onChange: (Double) -> Void
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geo in
            let shown = CGFloat(min(max(dragValue ?? value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geo.size.width * shown))
            }
            .frame(height: dragValue != nil ? 8 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let v = Double(min(max(drag.location.x / max(geo.size.width, 1), 0), 1))
                        dragValue = v
                        onChange(v)
                    }
                    .onEnded { _ in dragValue = nil }
            )
        }
        .frame(height: 18)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
        .animation(.easeOut(duration: 0.12), value: dragValue != nil)
    }
}

// MARK: - Liquid Glass

/// Flou de ce qui se trouve derrière la fenêtre (fond d'écran, fenêtres).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Fond du notch : noir quand il est fermé (il prolonge le notch matériel),
/// verre dépoli quand il est ouvert en thème Liquid Glass.
@MainActor
struct NotchSurface: View {
    let glass: Bool
    let tint: Double
    let notchHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectBackground()
                .opacity(glass ? 1 : 0)
            Color.black.opacity(glass ? tint : 1)
            // Le haut reste noir pour se fondre dans le notch physique et la barre des menus.
            LinearGradient(
                colors: [.black, .black.opacity(0.85), .black.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: notchHeight + 26)
            .opacity(glass ? 1 : 0)
            // Reflet spéculaire
            LinearGradient(
                colors: [.white.opacity(0.10), .white.opacity(0.02), .clear],
                startPoint: .topLeading, endPoint: .center
            )
            .opacity(glass ? 1 : 0)
            .blendMode(.plusLighter)
        }
    }
}

/// Carte « widget » en verre : fond légèrement éclairé + liseré lumineux.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.05), .white.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 10) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }
}

@MainActor
struct LevelBar: View {
    var value: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: value)
    }
}

/// Barre de progression cliquable / déplaçable.
@MainActor
struct SeekBar: View {
    var progress: Double
    var color: Color
    var onSeek: (Double) -> Void
    @State private var dragProgress: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let p = CGFloat(dragProgress ?? progress)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * p))
            }
            .frame(height: hovering || dragProgress != nil ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragProgress = Double(min(max(value.location.x / max(geo.size.width, 1), 0), 1))
                    }
                    .onEnded { value in
                        let fraction = Double(min(max(value.location.x / max(geo.size.width, 1), 0), 1))
                        onSeek(fraction)
                        dragProgress = nil
                    }
            )
        }
        .frame(height: 10)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.35 : 0.18)))
            .foregroundStyle(tint == .white ? Color.white : tint)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

@MainActor
struct BatteryBadge: View {
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        HStack(spacing: 4) {
            Text("\(battery.level)%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: battery.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(color)
        }
        .fixedSize()
        .help(battery.minutesRemaining.map { "Environ \($0 / 60) h \($0 % 60) min restantes" } ?? "Batterie")
    }

    private var color: Color {
        if battery.isCharging { return .green }
        if battery.level <= 20 && !battery.isPluggedIn { return .red }
        return .white
    }
}

@MainActor
struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
    }
}
