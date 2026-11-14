import SwiftUI

/// Boîte à outils : chronomètre, horloges mondiales, calculatrice / convertisseur, pipette.
@MainActor
struct ToolsView: View {
    var body: some View {
        HStack(spacing: 10) {
            StopwatchCard().glassCard()
            WorldClockCard().glassCard()
            CalculatorCard().glassCard()
            ColorPickerCard().frame(width: 128).glassCard()
        }
    }
}

// MARK: - Chronomètre

@MainActor
private struct StopwatchCard: View {
    @ObservedObject private var stopwatch = StopwatchService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(title: "Chronomètre", icon: "stopwatch.fill", color: .cyan)
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                Text(StopwatchService.format(stopwatch.elapsed(at: context.date)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(stopwatch.isRunning ? Color.cyan : Color.white)
            }
            HStack(spacing: 6) {
                Button(stopwatch.isRunning ? "Pause" : (stopwatch.hasTime ? "Reprendre" : "Démarrer")) {
                    stopwatch.toggle()
                }
                .buttonStyle(PillButtonStyle(tint: .cyan))
                Button(stopwatch.isRunning ? "Tour" : "Effacer") {
                    stopwatch.isRunning ? stopwatch.lap() : stopwatch.reset()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!stopwatch.hasTime)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(stopwatch.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("Tour \(stopwatch.laps.count - index)").foregroundStyle(.secondary)
                            Spacer()
                            Text(StopwatchService.format(lap)).monospacedDigit()
                        }
                        .font(.system(size: 10))
                    }
                }
            }
        }
    }
}

// MARK: - Horloges mondiales

@MainActor
private struct WorldClockCard: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(title: "Horloges", icon: "globe", color: .blue)
            if settings.worldClocks.isEmpty {
                Text("Ajoutez des villes dans Réglages → Agenda, météo & outils")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            TimelineView(.everyMinute) { context in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(settings.worldClocks, id: \.self) { identifier in
                            if let zone = TimeZone(identifier: identifier) {
                                row(zone, now: context.date)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(_ zone: TimeZone, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(WorldClock.city(zone.identifier))
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(WorldClock.offset(zone, now: now))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Image(systemName: WorldClock.isDaytime(zone, now: now) ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 9))
                .foregroundStyle(WorldClock.isDaytime(zone, now: now) ? Color.yellow : Color.indigo)
            Text(WorldClock.time(zone, now: now))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

enum WorldClock {
    static func city(_ identifier: String) -> String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ zone: TimeZone, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = zone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: now)
    }

    /// « +6 h, demain » / « −9 h » / « même heure »
    static func offset(_ zone: TimeZone, now: Date) -> String {
        let diff = zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        let hours = Double(diff) / 3600
        var text: String
        if diff == 0 {
            text = "Même heure"
        } else {
            let value = hours.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(hours)) : String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ",")
            text = (diff > 0 ? "+" : "") + value + " h"
        }
        var calendar = Calendar.current
        let localDay = calendar.component(.day, from: now)
        calendar.timeZone = zone
        let remoteDay = calendar.component(.day, from: now)
        if remoteDay != localDay { text += diff > 0 ? ", demain" : ", hier" }
        return text
    }

    static func isDaytime(_ zone: TimeZone, now: Date) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        return (7..<20).contains(hour)
    }
}

// MARK: - Calculatrice

@MainActor
private struct CalculatorCard: View {
    @ObservedObject private var calculator = Calculator.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(title: "Calcul & conversion", icon: "function", color: .orange)
            TextField("12*(3+4), 10 km en mi, 50 € en $…", text: $calculator.input)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                .onSubmit(copyResult)
            Group {
                if calculator.isLoading {
                    ProgressView().controlSize(.small)
                } else if let result = calculator.result {
                    Button(action: copyResult) {
                        HStack(spacing: 4) {
                            Text("= \(result)")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Copier le résultat (↩)")
                } else {
                    Text("Unités : km, mi, kg, lb, °c, °f, l, go, km/h… Devises : eur, usd, gbp, chf…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func copyResult() {
        guard let result = calculator.result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

// MARK: - Pipette

@MainActor
private struct ColorPickerCard: View {
    @ObservedObject private var picker = ColorPickerService.shared
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(title: "Pipette", icon: "eyedropper", color: .pink)
            Button {
                let model = vm
                model.close()
                picker.pick { model.open(tab: .tools) }
            } label: {
                Label("Choisir", systemImage: "eyedropper.halffull")
            }
            .buttonStyle(PillButtonStyle(tint: .pink))

            if let first = picker.recent.first {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5).fill(ColorPickerService.color(first)).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(first).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        Text(ColorPickerService.rgb(first)).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                }
                .onTapGesture { picker.copy(first) }
                .help("Copier")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(16), spacing: 5), count: 5), alignment: .leading, spacing: 5) {
                ForEach(picker.recent.dropFirst(), id: \.self) { hex in
                    Circle()
                        .fill(ColorPickerService.color(hex))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .frame(width: 16, height: 16)
                        .onTapGesture { picker.copy(hex) }
                        .help("\(hex) — cliquer pour copier")
                }
            }
            Spacer(minLength: 0)
            if let copied = picker.lastCopied {
                Text("\(copied) copié").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Composants

private struct ToolHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
        }
    }
}
