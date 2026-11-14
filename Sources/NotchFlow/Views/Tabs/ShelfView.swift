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

                VStack(alignment: .leading, spacing: 6) {
                    Button { shelf.airDrop(shelf.items) } label: {
                        Label("AirDrop", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .blue))

                    Button { shelf.zip(shelf.items) } label: {
                        Label("Compresser", systemImage: "doc.zipper")
                    }
                    .buttonStyle(PillButtonStyle(tint: .orange))
                    .help("Crée une archive .zip de tous les éléments")

                    if !shelf.items.compactMap(FileConverter.kind).isEmpty {
                        Menu {
                            ConvertMenu(urls: shelf.items)
                        } label: {
                            Label("Convertir", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .menuStyle(.button)
                        .buttonStyle(PillButtonStyle(tint: .purple))
                        .fixedSize()
                        .help("Convertisseur : images, PDF, documents, audio, vidéo")
                    }

                    Button { withAnimation { shelf.clear() } } label: {
                        Label("Vider", systemImage: "trash.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: .red))

                    if shelf.isWorking {
                        ProgressView().controlSize(.small)
                    } else if let error = shelf.lastError {
                        Text(error).font(.system(size: 9.5)).foregroundStyle(.orange)
                    }
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
            Button("Copier") { shelf.copyToPasteboard([url]) }
            Button("Compresser en .zip") { shelf.zip([url]) }
            if FileConverter.kind(of: url) != nil {
                Menu("Convertir") { ConvertMenu(urls: [url]) }
            }
            Divider()
            Button("Retirer de l'étagère", role: .destructive) { shelf.remove(url) }
        }
        .help(url.path)
    }
}

/// Menu du convertisseur : une section par type de fichier présent.
@MainActor
struct ConvertMenu: View {
    let urls: [URL]
    private var shelf: ShelfStore { .shared }

    var body: some View {
        let groups = Dictionary(grouping: urls) { FileConverter.kind(of: $0) }
        ForEach(FileConverter.Kind.allCases, id: \.self) { kind in
            if let files = groups[kind], !files.isEmpty {
                Section(urls.count > 1 ? "\(kind.title) (\(files.count))" : kind.title) {
                    ForEach(FileConverter.targets(for: kind, count: files.count)) { target in
                        Button(target.title) { shelf.convert(files, to: target) }
                    }
                    if kind == .image {
                        Menu("Réduire") {
                            Button("50 %") { shelf.convertImages(files, scale: 0.5) }
                            Button("1920 px max") { shelf.convertImages(files, maxPixels: 1920) }
                            Button("1280 px max") { shelf.convertImages(files, maxPixels: 1280) }
                            Button("JPEG léger (1600 px)") { shelf.convertImages(files, to: .jpeg, maxPixels: 1600) }
                        }
                    }
                }
            }
        }
    }
}
