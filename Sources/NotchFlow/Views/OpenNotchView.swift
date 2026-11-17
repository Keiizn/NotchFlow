import SwiftUI

@MainActor
struct OpenNotchView: View {
    let ns: Namespace.ID
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
                .frame(height: vm.notchSize.height)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .id(vm.tab)
                .transition(.opacity.combined(with: .move(edge: .bottom)).animation(.spring(response: 0.3, dampingFraction: 0.85)))
        }
        .padding(.horizontal, vm.earRadius + 14)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch vm.tab {
        case .home: HomeView(ns: ns)
        case .battery: BatteryView()
        case .apps: AppsView()
        case .shelf: ShelfView()
        case .timer: TimerView()
        case .tools: ToolsView()
        case .reminders: RemindersView()
        case .actions: ActionsView()
        case .notes: NotesView()
        case .clipboard: ClipboardView()
        case .system: SystemView()
        case .mirror: MirrorView()
        }
    }
}

/// Barre du haut : les onglets sont répartis de part et d'autre du notch physique.
@MainActor
struct HeaderBar: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var battery: BatteryService
    @EnvironmentObject private var settings: AppSettings
    @Namespace private var tabNamespace

    var body: some View {
        let tabs = vm.visibleTabs
        let split = (tabs.count + 1) / 2
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs.prefix(split)) { tabButton($0) }
            }
            .padding(2)
            .background(tabPill)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Zone masquée par le notch physique
            Color.clear.frame(width: vm.notchSize.width)

            HStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(tabs.dropFirst(split)) { tabButton($0) }
                }
                .padding(2)
                .background(tabPill)
                Spacer(minLength: 6)
                if battery.hasBattery && settings.showBatteryInHeader {
                    BatteryBadge().padding(.trailing, 8)
                }
                Button {
                    AppDelegate.shared.openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Réglages")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Pilule en verre derrière les onglets (thème Liquid Glass).
    private var tabPill: some View {
        let glass = settings.theme == .glass
        return Capsule()
            .fill(Color.white.opacity(glass ? 0.06 : 0.045))
            .overlay(Capsule().strokeBorder(Color.white.opacity(glass ? 0.12 : 0.07), lineWidth: 0.6))
    }

    private func tabButton(_ tab: NotchViewModel.Tab) -> some View {
        TabIconButton(tab: tab, selected: vm.tab == tab, namespace: tabNamespace) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { vm.tab = tab }
        }
    }
}

/// Onglet de la barre du haut : survol éclairé, onglet actif en pilule lumineuse.
@MainActor
private struct TabIconButton: View {
    let tab: NotchViewModel.Tab
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon)
                .font(.system(size: 11, weight: selected ? .bold : .semibold))
                .frame(width: 27, height: 22)
                .foregroundStyle(selected ? Color.white : Color.white.opacity(hovering ? 0.8 : 0.45))
                .background {
                    if selected {
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.12)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                            .matchedGeometryEffect(id: "tab", in: namespace)
                    } else if hovering {
                        Capsule().fill(Color.white.opacity(0.07))
                    }
                }
                .symbolEffect(.bounce, value: selected)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(tab.title)
    }
}
