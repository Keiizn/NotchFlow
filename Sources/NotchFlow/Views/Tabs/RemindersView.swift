import SwiftUI

@MainActor
struct RemindersView: View {
    @ObservedObject private var reminders = RemindersService.shared
    @State private var newTitle = ""
    @State private var completing: Set<String> = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if !reminders.isAuthorized {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text(reminders.isDenied ? "Accès aux Rappels refusé" : "Affichez et cochez vos rappels depuis le notch")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(reminders.isDenied ? "Ouvrir les réglages" : "Autoriser l'accès") {
                    reminders.isDenied ? reminders.openPrivacySettings() : reminders.requestAccess()
                }
                .buttonStyle(PillButtonStyle(tint: .orange))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Rappels")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(reminders.items.count)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button { reminders.openRemindersApp() } label: {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .help("Ouvrir Rappels")
                    }

                    if reminders.items.isEmpty {
                        Spacer(minLength: 0)
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text("Tout est fait ! 🎉").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(reminders.items) { item in
                                    row(item)
                                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                // Ajout rapide
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nouveau rappel")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Acheter du pain…", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($fieldFocused)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(fieldFocused ? 0.12 : 0.07)))
                        .onSubmit(add)
                    Button(action: add) {
                        Label("Ajouter", systemImage: "plus")
                    }
                    .buttonStyle(PillButtonStyle(tint: .orange))
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .frame(width: 190)
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        let done = completing.contains(item.id)
        return HStack(spacing: 8) {
            Button {
                completing.insert(item.id)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    reminders.complete(item)
                    completing.remove(item.id)
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableButtonStyle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
                    .lineLimit(1)
                if let due = item.dueDescription {
                    Text(due)
                        .font(.system(size: 10))
                        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: done)
    }

    private func add() {
        reminders.add(title: newTitle)
        newTitle = ""
    }
}
