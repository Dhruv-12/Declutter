import EventKit
import Foundation
import Testing
@testable import Declutter

@Suite("Calendar cleanup rules")
struct CalendarCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func candidate(_ id: String, daysAgo: Double, repeats: Bool = false, editable: Bool = true) -> EventCandidate {
        let end = now.addingTimeInterval(-daysAgo * 86_400)
        return EventCandidate(
            summary: EventSummary(id: id, title: id, start: end.addingTimeInterval(-3600), end: end,
                                  isAllDay: false, calendarTitle: "Home", color: [0, 0, 0]),
            repeats: repeats,
            calendarEditable: editable
        )
    }

    @Test func listsOnlyOldOneOffEventsInEditableCalendars() {
        let cutoff = EventAge.year.cutoff(from: now)
        let events = CalendarCleanup.cleanable([
            candidate("old", daysAgo: 400),
            candidate("recent", daysAgo: 30),
            candidate("repeating", daysAgo: 500, repeats: true),
            candidate("holiday", daysAgo: 600, editable: false),
            candidate("older", daysAgo: 800),
        ], cutoff: cutoff)
        #expect(events.map(\.id) == ["older", "old"], "Oldest first; recent, repeating and read-only left out")
    }

    @Test func eachEventIsListedOnce() {
        // The same event can come back from two overlapping search windows.
        let events = CalendarCleanup.cleanable([candidate("a", daysAgo: 400), candidate("a", daysAgo: 400)],
                                               cutoff: EventAge.month.cutoff(from: now))
        #expect(events.count == 1)
    }

    @Test func agesGetOlder() {
        let cutoffs = EventAge.allCases.map { $0.cutoff(from: now) }
        #expect(cutoffs == cutoffs.sorted(by: >))
        #expect(cutoffs.allSatisfy { $0 < now })
    }

    @Test func searchWindowsCoverTenYearsWithinEventKitsLimit() throws {
        let windows = CalendarCleanup.windows(endingAt: now)
        #expect(windows.count == CalendarCleanup.yearsBack)
        #expect(windows.first?.end == now)
        // Back to back with no gaps, each well under EventKit's four-year limit.
        for (newer, older) in zip(windows, windows.dropFirst()) {
            #expect(older.end == newer.start)
        }
        #expect(windows.allSatisfy { $0.duration <= 367 * 86_400 })
        #expect(CalendarCleanup.windows(endingAt: now, yearsBack: 0).isEmpty)
    }
}

/// Real events in the simulator's calendar; creates its own and removes them.
@Suite("Calendar store (simulator)", .serialized,
       .enabled(if: EKEventStore.authorizationStatus(for: .event) == .fullAccess, "Needs full Calendar access"))
struct CalendarStoreTests {
    private let store = EKEventStore()
    private let marker = "ZZDeclutterCalendarTest"

    private func add(_ title: String, daysAgo: Double, repeats: Bool = false) throws -> String {
        let event = EKEvent(eventStore: store)
        event.title = "\(marker) \(title)"
        event.startDate = Date.now.addingTimeInterval(-daysAgo * 86_400)
        event.endDate = event.startDate.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents
        if repeats {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)))
        }
        try store.save(event, span: .futureEvents, commit: true)
        return try #require(event.eventIdentifier)
    }

    private func cleanUp() throws {
        let predicate = store.predicateForEvents(withStart: .now.addingTimeInterval(-3 * 365 * 86_400), end: .now.addingTimeInterval(86_400), calendars: nil)
        for event in store.events(matching: predicate) where event.title?.hasPrefix(marker) == true {
            try store.remove(event, span: .futureEvents, commit: false)
        }
        try store.commit()
    }

    @Test func findsOldOneOffEventsAndDeletesThem() async throws {
        try cleanUp()
        defer { try? cleanUp() }
        let old = try add("old", daysAgo: 500)
        _ = try add("recent", daysAgo: 2)
        _ = try add("repeating", daysAgo: 600, repeats: true)

        let found = await CalendarService.oldEvents(endedBefore: EventAge.year.cutoff(from: .now))
            .filter { $0.title.hasPrefix(marker) }
        #expect(found.map(\.id) == [old])

        #expect(try await CalendarService.delete([old]) == 1)
        let remaining = await CalendarService.oldEvents(endedBefore: EventAge.year.cutoff(from: .now))
            .filter { $0.title.hasPrefix(marker) }
        #expect(remaining.isEmpty)
    }
}

/// Seeds the simulator calendar for the calendar UI tests. Runs only in Scripts/run-tests.sh's
/// "calendar-seed" phase.
@Suite("Calendar seeder",
       .enabled(if: ProcessInfo.processInfo.environment["DECLUTTER_PHASE"] == "calendar-seed", "Only seeds for UI tests"))
struct CalendarSeeder {
    @Test func seedOldEvents() throws {
        let store = EKEventStore()
        let calendar = try #require(store.defaultCalendarForNewEvents)
        func add(_ title: String, daysAgo: Double, repeats: Bool = false) throws {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = Date.now.addingTimeInterval(-daysAgo * 86_400)
            event.endDate = event.startDate.addingTimeInterval(3600)
            event.calendar = calendar
            if repeats {
                event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 4)))
            }
            try store.save(event, span: .futureEvents, commit: false)
        }
        // Three old one-off events are listed; the repeating and recent ones are not.
        try add("Dentist", daysAgo: 800)
        try add("Team offsite", daysAgo: 600)
        try add("Flight to Goa", daysAgo: 450)
        try add("Weekly class", daysAgo: 700, repeats: true)
        try add("Coffee", daysAgo: 3)
        try store.commit()
    }
}
