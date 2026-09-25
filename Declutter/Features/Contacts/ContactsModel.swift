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
    /// Only the newest scan may update the results, so a slow older scan can't overwrite them.
    @ObservationIgnored private var scanGeneration = 0

    /// Contacts that could go away: every contact in a group except the one that would be kept.
    var duplicateCount: Int { groups.reduce(0) { $0 + $1.contacts.count - 1 } }

    var selectedContacts: [ContactSummary] {
        groups.flatMap(\.contacts).filter { selection.contains($0.id) }
    }

    func scan() async {
        state = .scanning
        scanGeneration += 1
        let generation = scanGeneration
        do {
            let result = try await ContactsService.findDuplicates()
            guard generation == scanGeneration else { return }
            groups = result.groups
            totalContacts = result.totalContacts
            let ids = Set(result.groups.flatMap { $0.contacts.map(\.id) })
            selection.formIntersection(ids)
            state = .done
        } catch {
            guard generation == scanGeneration else { return }
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

    /// Merges one group exactly as edited in the merge editor.
    func merge(_ draft: MergeDraft) async throws {
        try await ContactsService.merge(draft.plan)
        await scan()
    }

    /// Merges each approved group in turn. One failure doesn't stop the rest.
    /// Returns a message for every group that couldn't be merged.
    func mergeAll(_ drafts: [MergeDraft], progress: (Int) -> Void) async -> [String] {
        var failures: [String] = []
        for (index, draft) in drafts.enumerated() {
            progress(index)
            do {
                try await ContactsService.merge(draft.plan)
            } catch {
                failures.append("\(draft.finalName): \(error.localizedDescription)")
            }
        }
        progress(drafts.count)
        await scan()
        return failures
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
