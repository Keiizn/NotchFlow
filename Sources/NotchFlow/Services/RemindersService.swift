import EventKit
import SwiftUI
import Combine

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let due: Date?
    let hasTime: Bool
    let color: Color
    let listName: String

    var isOverdue: Bool {
        guard let due else { return false }
        return hasTime ? due < Date() : Calendar.current.startOfDay(for: Date()) > due
    }

    var dueDescription: String? {
        guard let due else { return nil }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(due) { day = "Aujourd'hui" }
        else if cal.isDateInTomorrow(due) { day = "Demain" }
        else if cal.isDateInYesterday(due) { day = "Hier" }
        else { day = due.formatted(.dateTime.day().month(.abbreviated)) }
        return hasTime ? "\(day) · \(due.formatted(date: .omitted, time: .shortened))" : day
    }
}

/// Rappels (app Rappels) : liste, cochage, ajout rapide et alerte à l'échéance.
@MainActor
final class RemindersService: ObservableObject {
    static let shared = RemindersService()

    @Published private(set) var items: [ReminderItem] = []
    @Published private(set) var status: EKAuthorizationStatus = .notDetermined
    /// Émet le titre d'un rappel qui arrive à échéance.
    let dueEvents = PassthroughSubject<String, Never>()

    private let store = EKEventStore()
    private var timer: Timer?
    private var notified = Set<String>()

    var isAuthorized: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }

    private init() {
        status = EKEventStore.authorizationStatus(for: .reminder)
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkDue()
                self?.reload()
            }
        }
        reload()
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
            reload()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func reload() {
        guard isAuthorized else {
            if !items.isEmpty { items = [] }
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let mapped: [ReminderItem] = (reminders ?? []).map { reminder in
                let components = reminder.dueDateComponents
                return ReminderItem(
                    id: reminder.calendarItemIdentifier,
                    title: reminder.title ?? "Sans titre",
                    due: components.flatMap { Calendar.current.date(from: $0) },
                    hasTime: components?.hour != nil,
                    color: Color(cgColor: reminder.calendar?.cgColor ?? CGColor(red: 1, green: 0.6, blue: 0, alpha: 1)),
                    listName: reminder.calendar?.title ?? ""
                )
            }
            // Échéance la plus proche d'abord, puis les rappels sans date.
            let sorted = mapped.sorted { a, b in
                switch (a.due, b.due) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.title.localizedCompare(b.title) == .orderedAscending
                }
            }
            Task { @MainActor in
                guard let self else { return }
                if sorted != self.items { self.items = sorted }
            }
        }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            items.removeAll { $0.id == item.id }
        }
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAuthorized, !trimmed.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }

    /// Signale les rappels datés qui viennent d'arriver à échéance.
    private func checkDue() {
        let now = Date()
        for item in items where item.hasTime {
            guard let due = item.due, due <= now, now.timeIntervalSince(due) < 90,
                  !notified.contains(item.id) else { continue }
            notified.insert(item.id)
            dueEvents.send(item.title)
        }
    }
}
