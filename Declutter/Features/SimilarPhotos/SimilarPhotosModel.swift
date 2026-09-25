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
            // Keep the best photo of each group and pre-select the rest.
            selection = Set(result.groups.flatMap { $0.extras.map(\.id) })
            state = .done
        }
    }

    func cancelAndReset() {
        scanTask?.cancel()
        groups = []
        selection = []
        state = .idle
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
