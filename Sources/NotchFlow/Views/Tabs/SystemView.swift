import SwiftUI

@MainActor
struct SystemView: View {
    @EnvironmentObject private var system: SystemMonitor
    @EnvironmentObject private var battery: BatteryService

    var body: some View {
        HStack(spacing: 10) {
            StatTile(
                title: "Processeur",
                value: "\(Int((system.cpu * 100).rounded())) %",
                fraction: system.cpu,
                color: color(for: system.cpu),
                icon: "cpu"
            ) {
                Sparkline(values: system.cpuHistory, color: color(for: system.cpu))
            }
            StatTile(
                title: "Mémoire",
                value: Self.bytes(system.memoryUsed),
                fraction: system.memoryFraction,
                color: color(for: system.memoryFraction),
                icon: "memorychip",
                detail: "sur \(Self.bytes(system.memoryTotal))"
            )
            StatTile(
                title: "Disque",
                value: Self.bytes(system.diskFree),
                fraction: system.diskUsedFraction,
                color: color(for: system.diskUsedFraction),
                icon: "internaldrive",
                detail: "libres sur \(Self.bytes(system.diskTotal))"
            )
            if battery.hasBattery {
                StatTile(
                    title: "Batterie",
                    value: "\(battery.level) %",
                    fraction: Double(battery.level) / 100,
                    color: battery.isCharging ? .green : (battery.level <= 20 ? .red : .white),
                    icon: battery.symbolName,
                    detail: battery.isCharging ? "En charge" : (battery.isPluggedIn ? "Sur secteur" : remaining)
                )
            }
            StatTile(
                title: "Réseau",
                value: "↓ " + Self.rate(system.downloadRate),
                fraction: nil,
                color: .blue,
                icon: "network",
                detail: "↑ " + Self.rate(system.uploadRate)
            ) {
                let peak = max(system.downloadHistory.max() ?? 1, 1)
                Sparkline(values: system.downloadHistory.map { $0 / peak }, color: .blue)
            }
            StatTile(
                title: "Allumé depuis",
                value: Self.uptime(system.uptime),
                fraction: nil,
                color: .white,
                icon: "clock",
                detail: thermalLabel
            )
        }
        .onAppear { system.start() }
        .onDisappear { system.stop() }
    }

    private var remaining: String {
        guard let m = battery.minutesRemaining else { return "Sur batterie" }
        return "\(m / 60) h \(m % 60) restantes"
    }

    private var thermalLabel: String {
        switch system.thermal {
        case .nominal: "Température normale"
        case .fair: "Légèrement chaud"
        case .serious: "Chaud"
        case .critical: "Très chaud !"
        @unknown default: ""
        }
    }

    private func color(for fraction: Double) -> Color {
        fraction > 0.85 ? .red : fraction > 0.6 ? .orange : .green
    }

    static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86_400, hours = (total % 86_400) / 3600, minutes = (total % 3600) / 60
        if days > 0 { return "\(days) j \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }
}

@MainActor
struct StatTile<Accessory: View>: View {
    let title: String
    let value: String
    let fraction: Double?
    let color: Color
    let icon: String
    var detail: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())

            if let detail {
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory()
            if let fraction {
                LevelBar(value: fraction, color: color).frame(height: 5)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

extension StatTile where Accessory == EmptyView {
    init(title: String, value: String, fraction: Double?, color: Color, icon: String, detail: String? = nil) {
        self.init(title: title, value: value, fraction: fraction, color: color, icon: icon, detail: detail) { EmptyView() }
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count > 1 else { return }
                let step = geo.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let point = CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(max(v, 0), 1))))
                    i == 0 ? path.move(to: point) : path.addLine(to: point)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 18)
    }
}
