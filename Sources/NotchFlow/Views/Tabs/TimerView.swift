import SwiftUI

@MainActor
struct TimerView: View {
    @EnvironmentObject private var timer: TimerService
    private let presets: [Double] = [1, 5, 10, 15, 25, 45]

    var body: some View {
        if timer.isActive {
            activeView
        } else {
            presetsView
        }
    }

    private var activeView: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(timer.progress))
                    .stroke(
                        AngularGradient(colors: [.orange, .yellow, .orange], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: timer.progress)
                Text(timer.remainingString)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: timer.remainingString)
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 10) {
                Text(timer.isRunning ? "Minuteur en cours" : "En pause")
                    .font(.system(size: 14, weight: .semibold))
                Text("Fin prévue à \(Date().addingTimeInterval(timer.remaining).formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(timer.isRunning ? "Pause" : "Reprendre") {
                        timer.isRunning ? timer.pause() : timer.resume()
                    }
                    .buttonStyle(PillButtonStyle(tint: .orange))
                    Button("+1 min") { timer.add(minutes: 1) }
                        .buttonStyle(PillButtonStyle())
                    Button("Arrêter") { timer.stop() }
                        .buttonStyle(PillButtonStyle(tint: .red))
                }
            }
            Spacer()
        }
    }

    private var presetsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "timer").foregroundStyle(.orange)
                Text("Minuteur")
                    .font(.system(size: 14, weight: .semibold))
                Text("· Pomodoro, pause café, cuisson…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { minutes in
                    Button { timer.start(minutes: minutes) } label: {
                        VStack(spacing: 0) {
                            Text("\(Int(minutes))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                            Text("min")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 64, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(minutes == 25 ? Color.orange.opacity(0.22) : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help(minutes == 25 ? "Pomodoro" : "\(Int(minutes)) minutes")
                }
            }
        }
    }
}
