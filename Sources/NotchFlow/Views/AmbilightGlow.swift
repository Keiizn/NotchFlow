import SwiftUI

/// Halo façon Ambilight sous le notch fermé : dégradé des couleurs de la pochette
/// qui s'élargit et s'illumine au rythme du son (pulsation simulée si la capture
/// audio n'est pas autorisée).
@MainActor
struct AmbilightGlow: View {
    var colors: [Color]
    var intensity: Double
    var size: CGSize
    var cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40)) { context in
            let pulse = Self.pulse(at: context.date)
            let level = pulse.level
            let beat = pulse.beat
            let spread = 1 + 0.10 * level + 0.08 * beat
            RoundedRectangle(cornerRadius: max(cornerRadius, 8), style: .continuous)
                .fill(LinearGradient(colors: colors.count >= 2 ? colors : [.white, .white],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width, height: size.height)
                .scaleEffect(x: spread + 0.04 * beat, y: spread + 0.25 * level, anchor: .top)
                .blur(radius: 6 + 10 * intensity + 8 * level)
                .opacity(min(intensity * (0.35 + 0.65 * level) + 0.25 * beat, 1))
                .offset(y: 2)
        }
        .allowsHitTesting(false)
        .onAppear { AudioLevelMonitor.shared.acquire() }
        .onDisappear { AudioLevelMonitor.shared.release() }
    }

    /// Niveau réel si la capture audio fonctionne, sinon un battement simulé (~120 BPM).
    private static func pulse(at date: Date) -> (level: Double, beat: Double) {
        let monitor = AudioLevelMonitor.shared
        if monitor.isLive {
            return monitor.current()
        }
        let t = date.timeIntervalSinceReferenceDate
        let phase = (t * 2).truncatingRemainder(dividingBy: 1)   // 2 battements / s
        let beat = exp(-phase * 6)
        let level = 0.45 + 0.25 * sin(t * 1.3) * sin(t * 0.7) + 0.3 * beat
        return (min(max(level, 0), 1), beat)
    }
}
