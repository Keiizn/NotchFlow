import SwiftUI

@MainActor
struct ShelfView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject private var vm: NotchViewModel

    var body: some View {
        if shelf.items.isEmpty {
            emptyState
        } else {
            HStack(alignment: .top, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: shelf.items)
                }
                .overlay {
                    if vm.isDropTargeted {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }

                VStack(spacing: 8) {
                    Button { shelf.airDrop(shelf.items) } label: {
                        Label("AirDrop", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))

                    Button { withAnimation { shelf.clear() } } label: {
                        Label("Vider", systemImage: "trash.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .red))
                }
            }
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(vm.isDropTargeted ? Color.accentColor : Color.white.opacity(0.22))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 24))
                        .symbolEffect(.bounce, value: vm.isDropTargeted)
                    Text("Déposez des fichiers ici")
                        .font(.system(size: 12, weight: .medium))
                    Text("Ils restent à portée de main dans le notch")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(vm.isDropTargeted ? Color.accentColor : Color.white.opacity(0.7))
            }
            .scaleEffect(vm.isDropTargeted ? 1.02 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isDropTargeted)
    }
}

@MainActor
struct ShelfItemView: View {
    let url: URL
    @EnvironmentObject private var shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 74)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0))
        )
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Ouvrir") { shelf.open(url) }
            Button("Afficher dans le Finder") { shelf.reveal(url) }
            Button("Envoyer par AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Retirer de l'étagère", role: .destructive) { shelf.remove(url) }
        }
        .help(url.path)
    }
}
