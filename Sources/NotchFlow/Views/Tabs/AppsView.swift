import SwiftUI

@MainActor
struct AppsView: View {
    @EnvironmentObject private var launcher: AppLauncher
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let others = launcher.running.filter { app in
            !launcher.favorites.contains { $0.url.standardizedFileURL == app.bundleURL?.standardizedFileURL }
        }
        HStack(spacing: 10) {
            card(title: "Favoris", icon: "star.fill", color: .yellow, count: launcher.favorites.count) {
                ForEach(launcher.favorites) { item in
                    AppIconButton(
                        icon: launcher.icon(for: item.url),
                        name: item.name,
                        isRunning: launcher.isRunning(item)
                    ) {
                        launcher.launch(item)
                    }
                    .contextMenu {
                        Button("Ouvrir") { launcher.launch(item) }
                        Button("Afficher dans le Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        Divider()
                        Button("Retirer des favoris", role: .destructive) { launcher.removeFavorite(item) }
                    }
                }
                Button { launcher.pickApps() } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            )
                            .frame(width: 42, height: 42)
                            .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
                        Text("Ajouter")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 60)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Ajouter des applications aux favoris")
            }

            card(title: "Ouvertes", icon: "macwindow", color: .cyan, count: others.count) {
                if others.isEmpty {
                    Text("Aucune autre app ouverte")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(height: 64)
                } else {
                    ForEach(others, id: \.processIdentifier) { app in
                        AppIconButton(
                            icon: app.icon ?? NSImage(),
                            name: app.localizedName ?? "App",
                            isRunning: true
                        ) {
                            launcher.activate(app)
                        }
                        .contextMenu {
                            Button("Afficher") { launcher.activate(app) }
                            Button("Épingler aux favoris") { launcher.pinRunning(app) }
                            Divider()
                            Button("Quitter", role: .destructive) { launcher.quit(app) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func card<Content: View>(title: String, icon: String, color: Color, count: Int,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

@MainActor
struct AppIconButton: View {
    let icon: NSImage
    let name: String
    let isRunning: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 42, height: 42)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .scaleEffect(hovering ? 1.1 : 1)
                    .offset(y: hovering ? -2 : 0)
                Text(name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
                Circle()
                    .fill(Color.white.opacity(isRunning ? 0.85 : 0))
                    .frame(width: 4, height: 4)
            }
            .frame(width: 60)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .help(name)
    }
}
