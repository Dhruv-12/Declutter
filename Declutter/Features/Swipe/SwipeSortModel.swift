import Observation
import Photos

/// Swipe to sort: every photo, newest first, one card at a time. Keeps its place while you
/// use the rest of the app.
@Observable
final class SwipeSortModel {
    enum State: Equatable { case idle, loading, ready }

    private(set) var state: State = .idle
    private(set) var deck = SwipeDeck(count: 0)

    /// Marked photos with their sizes, looked up as each one is marked.
    @ObservationIgnored private var items: [String: MediaItem] = [:]
    @ObservationIgnored private var photos: PhotoList?

    /// Photos marked for deletion, in the order they were marked.
    var marked: [MediaItem] { deck.markedIDs.compactMap { items[$0] } }

    var current: PHAsset? { asset(at: deck.position) }

    func asset(at index: Int) -> PHAsset? { photos?.asset(at: index) }

    func load() async {
        guard state == .idle else { return }
        state = .loading
        let list = await PhotoList.load()
        photos = list
        deck = SwipeDeck(count: list.count)
        state = .ready
    }

    /// Forgets everything, for example when Photos access is turned off.
    func reset() {
        state = .idle
        deck = SwipeDeck(count: 0)
        items = [:]
        photos = nil
    }

    func decide(_ decision: SwipeDeck.Decision) {
        guard let asset = current else { return }
        if decision == .delete {
            items[asset.localIdentifier] = MediaItem(asset: asset, size: SizeCache.shared.size(of: asset))
        }
        deck.decide(decision, id: asset.localIdentifier)
    }

    func undo() { deck.undo() }

    func restart() { deck.restart() }

    /// Called after photos are deleted anywhere in the app.
    func remove(_ ids: Set<String>) {
        deck.forget(ids)
        for id in ids { items[id] = nil }
    }
}

/// Every photo in the library (not videos), newest first. Loaded lazily by the photo library.
nonisolated final class PhotoList: @unchecked Sendable {
    private let result: PHFetchResult<PHAsset>

    private init(result: PHFetchResult<PHAsset>) { self.result = result }

    var count: Int { result.count }

    func asset(at index: Int) -> PHAsset? {
        index >= 0 && index < result.count ? result.object(at: index) : nil
    }

    @concurrent
    static func load() async -> PhotoList {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PhotoList(result: PHAsset.fetchAssets(with: .image, options: options))
    }
}
