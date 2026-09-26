import EventKit
import SwiftUI

/// How old an event must be to be listed.
nonisolated enum EventAge: String, CaseIterable, Identifiable, Sendable {
    case month, sixMonths, year, twoYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "Older than 1 month"
        case .sixMonths: "Older than 6 months"
        case .year: "Older than 1 year"
        case .twoYears: "Older than 2 years"
        }
    }

    /// Events that ended before this date are listed.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date {
        let months = switch self {
        case .month: -1
        case .sixMonths: -6
        case .year: -12
        case .twoYears: -24
        }
        return calendar.date(byAdding: .month, value: months, to: now) ?? now
    }
}

/// A calendar event as the cleanup screen needs it. Safe to pass around the app.
nonisolated struct EventSummary: Identifiable, Hashable, Sendable {
    /// EventKit's event identifier.
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
    /// Calendar colour as RGB, 0...1.
    let color: [Double]

    var displayTitle: String { title.isEmpty ? "Untitled event" : title }

    var tint: Color {
        color.count == 3 ? Color(red: color[0], green: color[1], blue: color[2]) : Theme.slate
    }
}

/// What the filter needs to know about an event. Pure data, unit tested.
nonisolated struct EventCandidate: Sendable {
    let summary: EventSummary
    /// Repeating events are never listed, so a series can't be removed by accident.
    let repeats: Bool
    /// False for Holidays, Birthdays, subscribed calendars and others that can't be changed.
    let calendarEditable: Bool
}

/// Chooses which events to list. Pure logic, unit tested.
nonisolated enum CalendarCleanup {
    /// How far back to look.
    static let yearsBack = 10

    /// One-off events in editable calendars that ended before `cutoff`, oldest first,
    /// each listed once.
    static func cleanable(_ candidates: [EventCandidate], cutoff: Date) -> [EventSummary] {
        var seen = Set<String>()
        return candidates
            .filter { !$0.repeats && $0.calendarEditable && $0.summary.end < cutoff }
            .map(\.summary)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    /// Date ranges to search, newest first. EventKit only searches up to four years at once,
    /// so the span is split into one-year windows.
    static func windows(endingAt end: Date, yearsBack: Int = yearsBack, calendar: Calendar = .current) -> [DateInterval] {
        var windows: [DateInterval] = []
        var windowEnd = end
        for _ in 0..<max(yearsBack, 0) {
            guard let windowStart = calendar.date(byAdding: .year, value: -1, to: windowEnd) else { break }
            windows.append(DateInterval(start: windowStart, end: windowEnd))
            windowEnd = windowStart
        }
        return windows
    }
}

enum CalendarAccess: Equatable {
    case notDetermined, full, writeOnly, denied

    static var current: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .full
        case .writeOnly: .writeOnly
        default: .denied
        }
    }
}

/// Reads and deletes calendar events. Everything stays on the device.
nonisolated enum CalendarService {
    static func requestAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// Past events that could be cleaned up, oldest first.
    @concurrent
    static func oldEvents(endedBefore cutoff: Date) async -> [EventSummary] {
        let store = EKEventStore()
        var candidates: [EventCandidate] = []
        for window in CalendarCleanup.windows(endingAt: cutoff) {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
            for event in store.events(matching: predicate) {
                guard let id = event.eventIdentifier else { continue }
                let rgb = event.calendar.map { UIColor(cgColor: $0.cgColor) }.map { color -> [Double] in
                    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    return [red, green, blue].map(Double.init)
                } ?? []
                candidates.append(EventCandidate(
                    summary: EventSummary(
                        id: id,
                        title: event.title ?? "",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        calendarTitle: event.calendar?.title ?? "",
                        color: rgb
                    ),
                    repeats: event.hasRecurrenceRules,
                    calendarEditable: event.calendar?.allowsContentModifications ?? false
                ))
            }
        }
        return CalendarCleanup.cleanable(candidates, cutoff: cutoff)
    }

    /// Permanently deletes these events (only the single occurrence) and returns how many went.
    @concurrent
    static func delete(_ ids: [String]) async throws -> Int {
        let store = EKEventStore()
        var removed = 0
        for id in ids {
            guard let event = store.event(withIdentifier: id) else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
            removed += 1
        }
        try store.commit()
        return removed
    }
}
