import Foundation
import Observation

/// Old calendar events and what the user picked, kept while the app is open.
@Observable
final class CalendarCleanupModel {
    enum State: Equatable { case idle, loading, loaded }

    private(set) var access = CalendarAccess.current
    private(set) var state: State = .idle
    private(set) var events: [EventSummary] = []
    var selection: Set<String> = []

    var age: EventAge {
        didSet {
            UserDefaults.standard.set(age.rawValue, forKey: "eventAge")
            Task { await load() }
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "eventAge")
        age = saved.flatMap(EventAge.init(rawValue:)) ?? .year
    }

    var selectedEvents: [EventSummary] { events.filter { selection.contains($0.id) } }

    func refreshAccess() {
        access = CalendarAccess.current
    }

    func requestAccess() async {
        _ = await CalendarService.requestAccess()
        refreshAccess()
        if access == .full { await load() }
    }

    func load() async {
        refreshAccess()
        guard access == .full else {
            events = []
            selection = []
            state = .idle
            return
        }
        state = .loading
        events = await CalendarService.oldEvents(endedBefore: age.cutoff(from: .now))
        selection.formIntersection(events.map(\.id))
        state = .loaded
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Called after events are deleted.
    func remove(_ ids: Set<String>) {
        events.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }
}
