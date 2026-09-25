import Foundation
import Observation

/// Holds the similar-photo scan so it keeps running (and keeps its results) when you leave the screen.
@Observable
final class SimilarPhotosModel {
    enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case done
    }

    private(set) var state: State = .idle
    private(set) var groups: [SimilarGroup] = []
    private(set) var scannedCount = 0
    private(set) var scanDuration: TimeInterval?
    var selection: Set<String> = []
    /// True until the user has seen the latest results. Extras are only pre-selected once they have,
    /// so nothing they never looked at can end up in a cleanup.
    private(set) var hasUnseenResults = false

    var strictness: MatchStrictness {
        didSet {
            UserDefaults.standard.set(strictness.rawValue, forKey: "similarStrictness")
            scan()
        }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.string(forKey: "similarStrictness")
        strictness = saved.flatMap(MatchStrictness.init(rawValue:)) ?? .balanced
    }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    var extras: [MediaItem] { groups.flatMap(\.extras) }

    var selectedItems: [MediaItem] {
        groups.flatMap(\.items).filter { selection.contains($0.id) }
    }

    func scan() {
        scanTask?.cancel()
        state = .scanning(progress: 0)
        let strictness = strictness
        scanTask = Task { [weak self] in
            let start = Date.now
            let result = await SimilarPhotoScanner.scan(strictness: strictness) { [weak self] progress in
                guard let self, self.isScanning else { return }
                self.state = .scanning(progress: progress)
            }
            guard let self, !Task.isCancelled else { return }
            groups = result.groups
            scannedCount = result.scannedCount
            scanDuration = Date.now.timeIntervalSince(start)
            selection = []
            hasUnseenResults = !result.groups.isEmpty
            state = .done
        }
    }

    /// Called when the results are on screen: keep the best photo of each group and pre-select the rest.
    func resultsShown() {
        guard hasUnseenResults else { return }
        hasUnseenResults = false
        selection = Set(extras.map(\.id))
    }

    func cancelAndReset() {
        scanTask?.cancel()
        groups = []
        selection = []
        hasUnseenResults = false
        state = .idle
    }

    /// Drops deleted photos. Groups left with a single photo are no longer duplicates.
    func remove(_ ids: Set<String>) {
        groups = groups.compactMap { group in
            let remaining = group.items.filter { !ids.contains($0.id) }
            guard remaining.count > 1 else { return nil }
            let best = remaining.contains { $0.id == group.bestID } ? group.bestID : remaining[0].id
            return SimilarGroup(id: group.id, items: remaining, bestID: best)
        }
        selection.subtract(ids)
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Makes a different photo the one to keep. The old best becomes an extra and is selected.
    func setBest(_ id: String, in groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let oldBest = groups[index].bestID
        groups[index].bestID = id
        selection.remove(id)
        selection.insert(oldBest)
    }

    func selectExtras(in group: SimilarGroup, _ select: Bool) {
        let ids = group.extras.map(\.id)
        if select { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func selectAllExtras(_ select: Bool) {
        let ids = extras.map(\.id)
        if select { selection.formUnion(ids) } else { selection.subtract(ids) }
    }
}
