import SwiftUI

@MainActor
struct ActionsView: View {
    @ObservedObject private var actions = QuickActions.shared
    @ObservedObject private var volume = VolumeService.shared
    @ObservedObject private var brightness = BrightnessService.shared

    private let columns = Array(repeating: GridItem(.fixed(64), spacing: 6), count: 3)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Actions système
            LazyVGrid(columns: columns, spacing: 6) {
                tile("Verrouiller", "lock.fill", tint: .white) { actions.lockScreen() }
                tile("Veille écran", "moon.zzz.fill", tint: .indigo) { actions.sleepDisplay() }
                tile("Capture", "camera.viewfinder", tint: .white) { actions.screenshot() }
                tile(actions.isDarkMode ? "Mode clair" : "Mode sombre",
                     actions.isDarkMode ? "sun.max.fill" : "moon.fill",
                     tint: .purple, active: actions.isDarkMode) { actions.toggleDarkMode() }
                tile(actions.desktopHidden ? "Afficher bureau" : "Masquer bureau",
                     actions.desktopHidden ? "eye.slash.fill" : "menubar.dock.rectangle",
                     tint: .teal, active: actions.desktopHidden) { actions.toggleDesktopIcons() }
                tile("Anti-veille", "cup.and.saucer.fill",
                     tint: .orange, active: actions.isCaffeinated) { actions.toggleCaffeine() }
            }
            .frame(width: 204)

            VStack(alignment: .leading, spacing: 8) {
                // Volume et luminosité
                sliderRow(icon: CompactNotchView.volumeSymbol(level: volume.volume, muted: volume.isMuted),
                          value: volume.isMuted ? 0 : Double(volume.volume), color: .white) {
                    volume.setVolume(Float($0))
                } onIconTap: {
                    volume.toggleMute()
                }
                if brightness.isAvailable {
                    sliderRow(icon: "sun.max.fill", value: Double(brightness.brightness), color: .yellow) {
                        brightness.set(Float($0), notify: false)
                    } onIconTap: {}
                }

                // Raccourcis
                HStack {
                    Text("Raccourcis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { actions.openShortcutsApp() } label: {
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Ouvrir Raccourcis")
                }
                if actions.isLoadingShortcuts && actions.shortcuts.isEmpty {
                    ProgressView().controlSize(.small)
                } else if actions.shortcuts.isEmpty {
                    Text("Aucun raccourci. Créez-en dans l'app Raccourcis.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(actions.shortcuts, id: \.self) { name in
                                Button { actions.runShortcut(name) } label: {
                                    HStack(spacing: 4) {
                                        if actions.lastRun == name {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9))
                                        }
                                        Text(name).lineLimit(1)
                                    }
                                }
                                .buttonStyle(PillButtonStyle(tint: .blue))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            actions.refreshStates()
            volume.objectWillChange.send()
            brightness.read()
            if actions.shortcuts.isEmpty { actions.loadShortcuts() }
        }
    }

    private func tile(_ title: String, _ icon: String, tint: Color, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(active ? Color.black : tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(active ? tint : Color.white.opacity(0.1)))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 64, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
        .help(title)
    }

    private func sliderRow(icon: String, value: Double, color: Color,
                           onChange: @escaping (Double) -> Void, onIconTap: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: onIconTap) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())
            HUDSlider(value: value, color: color, onChange: onChange)
        }
    }
}
