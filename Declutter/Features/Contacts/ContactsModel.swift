import Contacts
import Foundation
import Observation

@Observable
final class ContactsModel {
    enum State: Equatable {
        case idle
        case scanning
        case done
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var groups: [ContactGroup] = []
    private(set) var totalContacts = 0
    var selection: Set<String> = []

    @ObservationIgnored private var changeObserver: Task<Void, Never>?

    /// Contacts that could go away: every contact in a group except the one that would be kept.
    var duplicateCount: Int { groups.reduce(0) { $0 + $1.contacts.count - 1 } }

    var selectedContacts: [ContactSummary] {
        groups.flatMap(\.contacts).filter { selection.contains($0.id) }
    }

    func scan() async {
        state = .scanning
        do {
            let result = try await ContactsService.findDuplicates()
            groups = result.groups
            totalContacts = result.totalContacts
            let ids = Set(result.groups.flatMap { $0.contacts.map(\.id) })
            selection.formIntersection(ids)
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
        observeChanges()
    }

    func reset() {
        changeObserver?.cancel()
        changeObserver = nil
        groups = []
        selection = []
        state = .idle
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func merge(_ group: ContactGroup) async throws {
        try await ContactsService.merge(group.contacts.map(\.id), into: group.primary.id)
        await scan()
    }

    func delete(_ ids: [String]) async throws {
        try await ContactsService.delete(ids)
        selection.subtract(ids)
        await scan()
    }

    /// Rescan when contacts change in another app (for example the Contacts app).
    private func observeChanges() {
        guard changeObserver == nil else { return }
        changeObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CNContactStoreDidChange) {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.state != .scanning else { continue }
                await self.scan()
            }
        }
    }
}
