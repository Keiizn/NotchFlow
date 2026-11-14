import SwiftUI

/// Boîte à outils : chronomètre, horloges mondiales, convertisseur de devises, pipette.
@MainActor
struct ToolsView: View {
    var body: some View {
        HStack(spacing: 10) {
            StopwatchCard().glassCard()
            WorldClockCard().glassCard()
            CurrencyCard().glassCard()
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

// MARK: - Devises

@MainActor
private struct CurrencyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToolHeader(title: "Convertisseur de devises", icon: "dollarsign.arrow.circlepath", color: .green)
            CurrencyConverterView()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Convertisseur de devises

@MainActor
private struct CurrencyConverterView: View {
    @ObservedObject private var service = CurrencyService.shared
    @AppStorage("currency.from") private var from = "EUR"
    @AppStorage("currency.to") private var to = "USD"
    @AppStorage("currency.amount") private var amountText = "100"
    @State private var copied = false

    private var amount: Double { MathExpression.number(amountText) ?? MathExpression.evaluate(amountText) ?? 0 }
    private var converted: Double? { service.convert(amount, from: from, to: to) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                TextField("Montant", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.08)))
                currencyMenu($from)
            }

            HStack(spacing: 4) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        let previous = from
                        from = to
                        to = previous
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Inverser")
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            HStack(spacing: 4) {
                Button(action: copy) {
                    HStack(spacing: 3) {
                        if let converted {
                            Text(CurrencyService.format(converted, decimals: 2))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(.green)
                                .contentTransition(.numericText())
                        } else if service.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(service.failed ? "Hors ligne" : "—")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if converted != nil {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .help("Copier le montant converti")
                currencyMenu($to)
            }
            .animation(.easeOut(duration: 0.2), value: converted)

            HStack(spacing: 3) {
                if let rate = service.rate(from: from, to: to) {
                    Text("1 \(from) = \(CurrencyService.format(rate, decimals: 4)) \(to)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Button { service.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(PressableButtonStyle())
                .help(service.formattedDate.map { "Taux BCE du \($0) — actualiser" } ?? "Actualiser les taux")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .onAppear { service.refreshIfNeeded() }
    }

    private func currencyMenu(_ selection: Binding<String>) -> some View {
        let current = CurrencyService.currency(selection.wrappedValue)
        return Menu {
            ForEach(CurrencyService.currencies) { currency in
                Button("\(currency.flag)  \(currency.code) — \(currency.name)") { selection.wrappedValue = currency.code }
            }
        } label: {
            Text("\(current.flag) \(current.code)")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.button)
        .buttonStyle(PillButtonStyle())
        .fixedSize()
    }

    private func copy() {
        guard let converted else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(CurrencyService.format(converted, decimals: 2), forType: .string)
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
