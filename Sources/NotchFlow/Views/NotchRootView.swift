import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var media: MediaController
    @ObservedObject private var privacy = PrivacyMonitor.shared
    @Namespace private var ns

    var body: some View {
        let size = vm.shapeSize
        ZStack(alignment: .top) {
            // Le contenu est disposé à sa taille FINALE (il ne se tasse jamais pendant
            // l'animation) : c'est la forme noire qui le révèle en s'agrandissant.
            content
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .modifier(NotchBackground(
            style: settings.style,
            isOpen: vm.isOpen,
            earRadius: vm.earRadius,
            bottomRadius: vm.bottomRadius,
            height: size.height,
            notchHeight: vm.notchSize.height,
            glass: settings.theme == .glass,
            glassTint: settings.glassTint
        ))
        .shadow(color: .black.opacity(vm.isOpen && settings.showShadow ? 0.4 : 0), radius: 22, y: 10)
        // Halo de la Live Activity : le notch fermé « s'allume » de la couleur de l'activité.
        .shadow(color: glow.opacity(!vm.isOpen && settings.showShadow ? 0.5 : 0), radius: 9, y: 2)
        .animation(.easeInOut(duration: 0.5), value: glow)
        .padding(.top, vm.topOffset)
        .contentShape(Rectangle())
        .onTapGesture { if !vm.isOpen { vm.open() } }
        .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            vm.handleDrop(providers)
        }
        .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
        .ignoresSafeArea()
        .animation(vm.isOpen ? NotchViewModel.openSpring : NotchViewModel.closeSpring, value: size)
        .environment(\.colorScheme, .dark)
        .onChange(of: vm.isDropTargeted) { _, targeted in
            if targeted { vm.open(tab: .shelf) }
        }
    }

    /// Couleur du halo selon l'activité affichée (transparent si rien).
    private var glow: Color {
        switch vm.activity {
        case .none: .clear
        case .music: media.isPlaying ? media.accentColor : .clear
        case .timer: .orange
        case .event: .blue
        case .stopwatch: .cyan
        case .download: .blue
        case .privacy: privacy.micInUse ? .orange : .green
        case .hud(let kind):
            switch kind {
            case .charging, .chargeLimited: .green
            case .timerDone, .reminder: .orange
            case .update, .downloadDone: .blue
            case .brightness: .yellow
            case .privacy(let mic, _): mic ? .orange : .green
            default: .white.opacity(0.5)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isOpen {
            OpenNotchView(ns: ns)
                .frame(width: vm.openSize.width, height: vm.openSize.height, alignment: .top)
                .transition(.asymmetric(
                    insertion: .modifier(
                        active: RevealEffect(progress: 0),
                        identity: RevealEffect(progress: 1)
                    )
                    .animation(.easeOut(duration: 0.28).delay(0.06)),
                    removal: .opacity.animation(.easeIn(duration: 0.08))
                ))
        } else {
            CompactNotchView(ns: ns)
                .frame(width: vm.closedSize.width, height: vm.closedSize.height, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                    removal: .opacity.animation(.easeIn(duration: 0.06))
                ))
        }
    }
}

/// Apparition du contenu : fondu + flou qui se dissipe + léger glissement depuis le notch.
private struct RevealEffect: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 10)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
            .offset(y: (1 - progress) * -8)
    }
}
