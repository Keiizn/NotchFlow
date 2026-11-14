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
    private let speeds: [Double] = [2.3, 3.1, 1.7, 2.8]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * speeds[i] + Double(i) * 1.3
                    let level = isPlaying ? 0.25 + 0.75 * abs(sin(phase) * cos(phase * 0.6)) : 0.2
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: 3, height: max(3, 16 * level))
                }
            }
        }
        .frame(width: 22, height: 16)
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
                .foregroundStyle(.white.opacity(0.85))
            Image(systemName: battery.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(color)
        }
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
