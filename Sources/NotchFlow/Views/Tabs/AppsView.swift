import SwiftUI

@MainActor
struct AppsView: View {
    @EnvironmentObject private var launcher: AppLauncher
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(title: "Favoris") {
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
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .semibold)))
                        Text("Ajouter").font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    .frame(width: 54)
                }
                .buttonStyle(PressableButtonStyle())
                .help("Ajouter des applications aux favoris")
            }

            let others = launcher.running.filter { app in
                !launcher.favorites.contains { $0.url.standardizedFileURL == app.bundleURL?.standardizedFileURL }
            }
            if !others.isEmpty {
                section(title: "Ouvertes") {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) { content() }
            }
        }
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
                    .frame(width: 38, height: 38)
                    .scaleEffect(hovering ? 1.12 : 1)
                    .offset(y: hovering ? -2 : 0)
                Text(name)
                    .font(.system(size: 9.5))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
                Circle()
                    .fill(Color.white.opacity(isRunning ? 0.7 : 0))
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(width: 54)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .help(name)
    }
}
