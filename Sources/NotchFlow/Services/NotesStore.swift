import AppKit

/// Bloc-notes rapide, sauvegardé automatiquement.
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published var text: String {
        didSet { scheduleSave() }
    }

    private let key = "notes.text"
    private var saveTask: Task<Void, Never>?

    private init() {
        text = UserDefaults.standard.string(forKey: key) ?? ""
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clear() {
        text = ""
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let value = text
        let key = key
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}
