import EventKit
import SwiftUI

struct CalendarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let meetingURL: URL?

    var isOngoing: Bool {
        let now = Date()
        return start <= now && end > now
    }

    var timeDescription: String {
        let cal = Calendar.current
        let prefix = cal.isDateInTomorrow(start) ? "Demain · " : ""
        if isAllDay { return prefix + "Toute la journée" }
        if isOngoing { return "En cours · jusqu'à \(end.formatted(date: .omitted, time: .shortened))" }
        return prefix + "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [CalendarItem] = []
    @Published private(set) var status: EKAuthorizationStatus = .notDetermined
    @Published private(set) var now = Date()

    private let store = EKEventStore()
    private var timer: Timer?

    var isAuthorized: Bool { status == .fullAccess }
    var isDenied: Bool { status == .denied || status == .restricted }

    /// Prochain événement qui commence dans les 10 minutes.
    var upcomingSoon: CalendarItem? {
        events.first { !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= 600 }
    }

    private init() {
        status = EKEventStore.authorizationStatus(for: .event)

        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }

        if status == .notDetermined {
            requestAccess()
        } else {
            reload()
        }
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            reload()
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        now = Date()
        guard isAuthorized else {
            if !events.isEmpty { events = [] }
            return
        }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 2, to: startOfDay) else { return }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: end, calendars: nil)
        let reference = now
        let items: [CalendarItem] = store.events(matching: predicate)
            .filter { $0.endDate > reference }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                CalendarItem(
                    id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "Sans titre",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar?.color ?? .systemBlue),
                    location: event.location,
                    meetingURL: Self.meetingURL(for: event)
                )
            }
        if items != events { events = items }
    }

    /// Détecte un lien de visio (Zoom, Meet, Teams, Webex…) dans l'événement.
    private static func meetingURL(for event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        let pattern = #"https?://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com)[^\s<>"]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let r = Range(match.range, in: text) {
                return URL(string: String(text[r]))
            }
        }
        return nil
    }
}
