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
    @ViewBuilder
    private var tabPill: some View {
        if settings.theme == .glass {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
        }
    }

    private func tabButton(_ tab: NotchViewModel.Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.tab = tab }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 27, height: 22)
                .foregroundStyle(vm.tab == tab ? Color.white : Color.white.opacity(0.45))
                .background {
                    if vm.tab == tab {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .matchedGeometryEffect(id: "tab", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .help(tab.title)
    }
}
