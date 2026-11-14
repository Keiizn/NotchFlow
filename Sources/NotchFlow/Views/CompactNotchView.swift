import SwiftUI

/// Notch fermé : les « Live Activities » s'affichent de part et d'autre du notch physique.
@MainActor
struct CompactNotchView: View {
    let ns: Namespace.ID

    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var media: MediaController
    @EnvironmentObject private var timer: TimerService
    @EnvironmentObject private var calendar: CalendarService

    var body: some View {
        let activity = vm.activity
        let side = vm.sideWidth(for: activity)
        let height = vm.notchSize.height

        HStack(spacing: 0) {
            leading(activity)
                .frame(width: side, height: height)
            Spacer(minLength: 0)
            trailing(activity)
                .frame(width: side, height: height)
        }
        .padding(.horizontal, vm.earRadius)
        .frame(height: height)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activity)
    }

    // MARK: - Côté gauche

    @ViewBuilder
    private func leading(_ activity: NotchViewModel.Activity) -> some View {
        switch activity {
        case .none:
            EmptyView()
        case .music:
            ArtworkView(image: media.artwork, cornerRadius: 6)
                .matchedGeometryEffect(id: "artwork", in: ns)
                .frame(width: vm.notchSize.height - 10, height: vm.notchSize.height - 10)
                .transition(.scale.combined(with: .opacity))
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
        case .event:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(calendar.upcomingSoon?.color ?? .blue)
        case .hud(let kind):
            hudLeading(kind)
        }
    }

    // MARK: - Côté droit

    @ViewBuilder
    private func trailing(_ activity: NotchViewModel.Activity) -> some View {
        switch activity {
        case .none:
            EmptyView()
        case .music:
            AudioBars(color: media.accentColor, isPlaying: media.isPlaying)
        case .timer:
            Text(timer.remainingString)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.orange)
                .contentTransition(.numericText(countsDown: true))
        case .event:
            if let event = calendar.upcomingSoon {
                let minutes = max(1, Int(event.start.timeIntervalSince(calendar.now) / 60))
                Text("dans \(minutes) min")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        case .hud(let kind):
            hudTrailing(kind)
        }
    }

    // MARK: - HUD

    @ViewBuilder
    private func hudLeading(_ kind: NotchViewModel.HUD) -> some View {
        switch kind {
        case .volume(let level, let muted):
            Image(systemName: Self.volumeSymbol(level: level, muted: muted))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
                .symbolEffect(.pulse)
        case .unplugged:
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        case .timerDone:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: kind)
        }
    }

    @ViewBuilder
    private func hudTrailing(_ kind: NotchViewModel.HUD) -> some View {
        switch kind {
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level), color: .white)
                .frame(width: 54, height: 5)
        case .charging(let level):
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: "battery.100.bolt").foregroundStyle(.green)
            }
            .foregroundStyle(.white)
        case .unplugged(let level):
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Image(systemName: "battery.75")
            }
            .foregroundStyle(.white.opacity(0.85))
        case .timerDone:
            Text("Terminé")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    static func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
