import SwiftUI

@MainActor
struct ClipboardView: View {
    @EnvironmentObject private var clipboard: ClipboardService
    @EnvironmentObject private var settings: AppSettings
    @State private var copiedID: UUID?

    var body: some View {
        if !settings.clipboardEnabled {
            placeholder(icon: "doc.on.clipboard", text: "L'historique du presse-papiers est désactivé") {
                Button("Activer") { settings.clipboardEnabled = true }
                    .buttonStyle(PillButtonStyle(tint: .blue))
            }
        } else if clipboard.items.isEmpty {
            placeholder(icon: "doc.on.clipboard", text: "Copiez du texte : il apparaîtra ici") { EmptyView() }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(clipboard.items) { item in
                            card(item)
                        }
                    }
                }
                Button { clipboard.clear() } label: {
                    Image(systemName: "trash.fill")
                }
                .buttonStyle(PillButtonStyle(tint: .red))
                .help("Effacer l'historique")
            }
        }
    }

    private func card(_ item: ClipboardService.Item) -> some View {
        Button {
            clipboard.copy(item)
            copiedID = item.id
            let id = item.id
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if copiedID == id { copiedID = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 11))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack {
                    Text(item.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if copiedID == item.id {
                        Label("Copié", systemImage: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(10)
            .frame(width: 160)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(copiedID == item.id ? 0.14 : 0.07))
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: copiedID)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button("Supprimer", role: .destructive) { clipboard.remove(item) }
        }
    }

    private func placeholder<Accessory: View>(icon: String, text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.35))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            accessory()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
