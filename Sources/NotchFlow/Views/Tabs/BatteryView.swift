import SwiftUI

/// Onglet Batterie : état de charge, limiteur façon AlDente et santé de la batterie.
@MainActor
struct BatteryView: View {
    @EnvironmentObject private var battery: BatteryService
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = BatteryManager.shared

    var body: some View {
        if !battery.hasBattery {
            placeholder(icon: "powerplug.fill", text: "Aucune batterie détectée sur ce Mac")
        } else {
            HStack(spacing: 10) {
                levelCard
                    .frame(width: 150)
                    .glassCard()
                controlsCard
                    .glassCard()
                healthCard
                    .frame(width: 150)
                    .glassCard()
            }
        }
    }

    // MARK: - Niveau

    private var levelCard: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(battery.level) / 100)
                    .stroke(levelColor.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if manager.isLimiterActive {
                    // Repère de la limite
                    Circle()
                        .trim(from: CGFloat(settings.chargeLimit) / 100 - 0.004, to: CGFloat(settings.chargeLimit) / 100 + 0.004)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text("\(battery.level)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: modeIcon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(levelColor)
                        .symbolEffect(.pulse, isActive: manager.mode == .charging || manager.mode == .discharging)
                }
            }
            .frame(width: 78, height: 78)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: battery.level)

            Text(modeText)
                .font(.system(size: 10.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(levelColor)
            Text(powerText)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Contrôles

    @ViewBuilder
    private var controlsCard: some View {
        switch manager.helperState {
        case .checking:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notInstalled, .outdated:
            VStack(alignment: .leading, spacing: 6) {
                Label("Gestion de charge", systemImage: "leaf.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text(manager.helperState == .outdated
                     ? "Une mise à jour de l'assistant de charge est nécessaire."
                     : "Limitez la charge à 80 % pour préserver la batterie. Un assistant doit être installé une fois (mot de passe administrateur).")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(manager.helperState == .outdated ? "Mettre à jour l'assistant" : "Installer l'assistant") {
                    manager.installHelper()
                }
                .buttonStyle(PillButtonStyle(tint: .green))
                if let error = manager.lastError {
                    Text(error).font(.system(size: 9.5)).foregroundStyle(.orange)
                }
            }
        case .unsupported:
            placeholder(icon: "exclamationmark.triangle.fill", text: "La gestion de charge n'est pas prise en charge par ce Mac.")
        case .ready:
            VStack(alignment: .leading, spacing: 7) {
                Toggle(isOn: $settings.chargeLimiterEnabled) {
                    Text("Limiter la charge").font(.system(size: 12, weight: .semibold))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.green)

                HStack(spacing: 8) {
                    Text("\(settings.chargeLimit) %")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                        .foregroundStyle(settings.chargeLimiterEnabled ? Color.green : Color.secondary)
                    HUDSlider(value: Double(settings.chargeLimit - 20) / 80, color: settings.chargeLimiterEnabled ? .green : .gray) { fraction in
                        let value = 20 + Int((fraction * 80 / 5).rounded()) * 5
                        if value != settings.chargeLimit { settings.chargeLimit = value }
                    }
                }
                .opacity(settings.chargeLimiterEnabled ? 1 : 0.5)

                HStack(spacing: 6) {
                    Button {
                        manager.topUpActive.toggle()
                    } label: {
                        Label(manager.topUpActive ? "Annuler 100 %" : "Charger à 100 %", systemImage: "bolt.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: manager.topUpActive ? .orange : .white))
                    .disabled(!settings.chargeLimiterEnabled)

                    Button {
                        settings.dischargeToLimit.toggle()
                    } label: {
                        Label("Décharger", systemImage: settings.dischargeToLimit ? "arrow.down.circle.fill" : "arrow.down.circle")
                    }
                    .buttonStyle(PillButtonStyle(tint: settings.dischargeToLimit ? .blue : .white))
                    .help("Décharge la batterie jusqu'à la limite même branché")
                    .disabled(!settings.chargeLimiterEnabled)
                }
                if let error = manager.lastError {
                    Text(error).font(.system(size: 9.5)).foregroundStyle(.orange).lineLimit(2)
                }
            }
        }
    }

    // MARK: - Santé

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Santé").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            stat("heart.fill", "Capacité", manager.health.healthPercent > 0 ? "\(manager.health.healthPercent) %" : "—",
                 color: manager.health.healthPercent >= 80 ? .green : .orange)
            stat("arrow.triangle.2.circlepath", "Cycles", "\(manager.health.cycleCount)", color: .white)
            stat("thermometer.medium", "Température", String(format: "%.1f °C", manager.health.temperature),
                 color: manager.health.temperature >= settings.heatLimit ? .red : .white)
            stat("powerplug.fill", "Adaptateur", manager.health.adapterWatts > 0 ? "\(manager.health.adapterWatts) W" : "—", color: .white)
        }
    }

    private func stat(_ icon: String, _ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).frame(width: 12)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 10.5, weight: .semibold)).monospacedDigit().foregroundStyle(color)
        }
    }

    // MARK: - Textes

    private var modeText: String {
        switch manager.mode {
        case .onBattery: battery.minutesRemaining.map { "Sur batterie · \($0 / 60) h \($0 % 60)" } ?? "Sur batterie"
        case .charging: manager.isLimiterActive ? "En charge jusqu'à \(manager.topUpActive ? 100 : settings.chargeLimit) %" : "En charge"
        case .limitReached: "Limite atteinte · alimenté par le secteur"
        case .sailing: "En pause · reprise sous \(settings.chargeLimit - settings.sailingRange) %"
        case .discharging: "Décharge vers \(settings.chargeLimit) %"
        case .tooHot: "Pause : batterie chaude"
        case .full: "Chargée"
        case .notManaged: battery.isPluggedIn ? "Branché" : "Sur batterie"
        }
    }

    private var modeIcon: String {
        switch manager.mode {
        case .charging: "bolt.fill"
        case .limitReached, .sailing: "leaf.fill"
        case .discharging: "arrow.down"
        case .tooHot: "thermometer.high"
        case .full: "checkmark"
        case .onBattery, .notManaged: battery.isPluggedIn ? "powerplug.fill" : "battery.75"
        }
    }

    private var levelColor: Color {
        switch manager.mode {
        case .charging, .full: .green
        case .limitReached, .sailing: .mint
        case .discharging: .blue
        case .tooHot: .red
        default: battery.level <= 20 ? .red : .white
        }
    }

    private var powerText: String {
        let watts = manager.health.batteryWatts
        guard abs(watts) >= 0.5 else { return battery.isPluggedIn ? "Batterie au repos" : "" }
        return watts > 0 ? String(format: "+%.1f W vers la batterie", watts) : String(format: "%.1f W consommés", abs(watts))
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
