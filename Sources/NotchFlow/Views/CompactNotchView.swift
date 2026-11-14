import SwiftUI

/// Notch fermé : les « Live Activities » s'affichent de part et d'autre du notch physique.
@MainActor
struct CompactNotchView: View {
    let ns: Namespace.ID

    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var media: MediaController
    @EnvironmentObject private var timer: TimerService
    @EnvironmentObject private var calendar: CalendarService
    @ObservedObject private var stopwatch = StopwatchService.shared
    @ObservedObject private var downloads = DownloadMonitor.shared
    @ObservedObject private var privacy = PrivacyMonitor.shared

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
        case .stopwatch:
            Image(systemName: "stopwatch.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.cyan)
        case .download:
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                if let fraction = downloads.overallFraction {
                    Circle()
                        .trim(from: 0, to: CGFloat(fraction))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: fraction)
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.blue)
            }
            .frame(width: 17, height: 17)
        case .privacy:
            if privacy.micInUse {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                    .help(privacy.micApp.map { "Micro utilisé par \($0)" } ?? "Micro utilisé")
            }
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
        case .stopwatch:
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(StopwatchService.format(stopwatch.elapsed(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
            }
        case .download:
            Text(downloads.overallFraction.map { "\(Int(($0 * 100).rounded())) %" }
                 ?? ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.blue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        case .privacy:
            if privacy.cameraInUse {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                    .help("Caméra utilisée")
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
        case .update:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)
        case .brightness(let level):
            Image(systemName: level < 0.35 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.yellow)
                .contentTransition(.symbolEffect(.replace))
        case .reminder:
            Image(systemName: "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: kind)
        case .chargeLimited:
            Image(systemName: "leaf.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: kind)
        case .device(_, let icon, _, let connected):
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(connected ? Color.white : Color.white.opacity(0.45))
                .symbolEffect(.bounce, value: connected)
        case .privacy(let mic, _):
            Image(systemName: mic ? "mic.fill" : "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mic ? Color.orange : Color.green)
                .symbolEffect(.pulse)
        case .downloadDone:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .symbolEffect(.bounce, value: kind)
        case .screenshot:
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: kind)
        case .skip(let forward):
            Image(systemName: forward ? "forward.fill" : "backward.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: kind)
        }
    }

    @ViewBuilder
    private func hudTrailing(_ kind: NotchViewModel.HUD) -> some View {
        switch kind {
        case .volume(let level, let muted):
            // Curseur réglable directement à la souris
            HUDSlider(value: muted ? 0 : Double(level)) { VolumeService.shared.setVolume(Float($0)) }
                .frame(width: 60)
        case .brightness(let level):
            HUDSlider(value: Double(level), color: .yellow) { BrightnessService.shared.set(Float($0)) }
                .frame(width: 60)
        case .chargeLimited(let limit):
            HStack(spacing: 3) {
                Text("\(limit) %").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Text("max").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.green)
        case .reminder(let title):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
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
        case .update(let version):
            Text("v\(version)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.blue)
        case .device(_, _, let battery, let connected):
            if let battery, connected {
                HStack(spacing: 3) {
                    Text("\(battery) %").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Image(systemName: Self.batterySymbol(battery))
                        .foregroundStyle(battery <= 20 ? Color.red : Color.green)
                }
                .foregroundStyle(.white)
            } else {
                Text(connected ? "Connecté" : "Déconnecté")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(connected ? Color.white : Color.white.opacity(0.6))
            }
        case .privacy(let mic, let app):
            Text(app ?? (mic ? "Micro" : "Caméra"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mic ? Color.orange : Color.green)
                .lineLimit(1)
        case .downloadDone(let name):
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
        case .screenshot:
            Text("Étagère")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        case .skip(let forward):
            Text(forward ? "Suivant" : "Précédent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }

    static func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
