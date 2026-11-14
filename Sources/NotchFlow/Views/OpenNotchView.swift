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
        case .shelf: ShelfView()
        case .timer: TimerView()
        case .clipboard: ClipboardView()
        case .mirror: MirrorView()
        }
    }
}

@MainActor
struct HeaderBar: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var battery: BatteryService
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(NotchViewModel.Tab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.tab = tab }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 28, height: 22)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // Zone masquée par le notch physique
            Color.clear.frame(width: vm.notchSize.width)

            HStack(spacing: 12) {
                if battery.hasBattery { BatteryBadge() }
                Button {
                    AppDelegate.shared.openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Réglages")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
