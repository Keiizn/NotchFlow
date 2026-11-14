import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct NotchRootView: View {
    @EnvironmentObject private var vm: NotchViewModel
    @EnvironmentObject private var settings: AppSettings
    @Namespace private var ns

    var body: some View {
        let size = vm.shapeSize
        ZStack(alignment: .top) {
            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .modifier(NotchBackground(
                    style: settings.style,
                    isOpen: vm.isOpen,
                    earRadius: vm.earRadius,
                    bottomRadius: vm.bottomRadius,
                    height: size.height
                ))
                .shadow(color: .black.opacity(vm.isOpen && settings.showShadow ? 0.5 : 0), radius: 16, y: 6)
                .scaleEffect(vm.isHovering && !vm.isOpen && settings.hoverGrow ? 1.06 : 1, anchor: .top)
                .padding(.top, vm.topOffset)
                .onTapGesture { if !vm.isOpen { vm.open() } }
                .onDrop(of: [UTType.fileURL], isTargeted: $vm.isDropTargeted) { providers in
                    vm.handleDrop(providers)
                }
        }
        .frame(width: vm.windowSize.width, height: vm.windowSize.height, alignment: .top)
        .ignoresSafeArea()
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: size)
        .environment(\.colorScheme, .dark)
        .onChange(of: vm.isDropTargeted) { _, targeted in
            if targeted { vm.open(tab: .shelf) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isOpen {
            OpenNotchView(ns: ns)
                .transition(.asymmetric(
                    insertion: .opacity
                        .combined(with: .scale(scale: 0.92, anchor: .top))
                        .combined(with: .offset(y: -6)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else {
            CompactNotchView(ns: ns)
                .transition(.opacity)
        }
    }
}
