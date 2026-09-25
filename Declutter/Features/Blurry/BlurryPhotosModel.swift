import Foundation
import Observation

/// Keeps the blurry-photo scan and its results while you use the rest of the app.
@Observable
final class BlurryPhotosModel {
    enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case done
    }

    private(set) var state: State = .idle
    /// Every photo under the loosest level, blurriest first.
    private(set) var candidates: [BlurryPhoto] = []
    private(set) var scannedCount = 0
    var selection: Set<String> = []

    var level: BlurLevel {
        didSet {
            UserDefaults.standard.set(level.rawValue, forKey: "blurLevel")
            // Changing the level only filters; forget selections that are no longer listed.
            selection.formIntersection(photos.map(\.id))
        }
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanID = 0

    init() {
        let saved = UserDefaults.standard.string(forKey: "blurLevel")
        level = saved.flatMap(BlurLevel.init(rawValue:)) ?? .blurry
    }

    /// Photos at the chosen level, blurriest first.
    var photos: [BlurryPhoto] { candidates.filter { $0.score < level.threshold } }

    var items: [MediaItem] { photos.map(\.item) }

    var selectedItems: [MediaItem] { items.filter { selection.contains($0.id) } }

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    func scan() {
        scanTask?.cancel()
        scanID += 1
        let id = scanID
        state = .scanning(progress: 0)
        // Low priority: the scan uses every CPU core, and the interface should stay smooth meanwhile.
        scanTask = Task(priority: .utility) { [weak self] in
            let result = await BlurryPhotoScanner.scan { [weak self] progress in
                guard let self, self.scanID == id, self.isScanning else { return }
                self.state = .scanning(progress: progress)
            }
            guard let self, self.scanID == id, !Task.isCancelled else { return }
            candidates = result.photos
            scannedCount = result.scannedCount
            selection.formIntersection(result.photos.map(\.id))
            state = .done
        }
    }

    func reset() {
        scanTask?.cancel()
        scanID += 1
        candidates = []
        selection = []
        state = .idle
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Called after photos are deleted anywhere in the app.
    func remove(_ ids: Set<String>) {
        candidates.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }
}
