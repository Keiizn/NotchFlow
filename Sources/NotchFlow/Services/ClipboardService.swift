import AppKit

/// Historique local du presse-papiers (texte uniquement, mots de passe ignorés).
@MainActor
final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let date: Date
    }

    @Published private(set) var items: [Item] = []
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxItems = 30
    private let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard AppSettings.shared.clipboardEnabled else { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: concealedTypes) else { return }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        items.removeAll { $0.text == text }
        items.insert(Item(text: text, date: Date()), at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
    }

    func copy(_ item: Item) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        items.removeAll { $0.id == item.id }
        items.insert(Item(text: item.text, date: Date()), at: 0)
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.removeAll()
    }
}
