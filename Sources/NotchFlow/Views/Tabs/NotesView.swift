import SwiftUI

@MainActor
struct NotesView: View {
    @EnvironmentObject private var notes: NotesStore
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(6)
                if notes.text.isEmpty {
                    Text("Écrivez une idée, une liste, un numéro…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(focused ? 0.5 : 0), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.15), value: focused)

            VStack(spacing: 8) {
                Button { notes.copyAll() } label: { Label("Copier", systemImage: "doc.on.doc.fill") }
                    .buttonStyle(PillButtonStyle(tint: .yellow))
                Button { notes.clear() } label: { Label("Effacer", systemImage: "trash.fill") }
                    .buttonStyle(PillButtonStyle(tint: .red))
                Spacer()
                Text("\(notes.wordCount) mot\(notes.wordCount > 1 ? "s" : "")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
