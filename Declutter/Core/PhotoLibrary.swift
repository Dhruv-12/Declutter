import Photos

/// A photo or video plus how much space it takes on the device.
nonisolated struct MediaItem: Identifiable, Hashable, @unchecked Sendable {
    let asset: PHAsset
    let size: Int64

    var id: String { asset.localIdentifier }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Array where Element == MediaItem {
    nonisolated var totalSize: Int64 { reduce(0) { $0 + $1.size } }
}

nonisolated struct DashboardMedia: @unchecked Sendable {
    let screenshots: [MediaItem]
    let videos: [MediaItem]
}

/// Reads from the photo library. All work here runs off the main thread.
nonisolated enum PhotoLibrary {
    @concurrent
    static func loadDashboardMedia() async -> DashboardMedia {
        let screenshots = sized(fetchScreenshots())
        let videos = sized(fetchVideos()).sorted { $0.size > $1.size }
        return DashboardMedia(screenshots: screenshots, videos: videos)
    }

    /// Which of these photos still exist, looked up off the main thread.
    @concurrent
    static func existingIDs(_ ids: [String]) async -> Set<String> {
        var existing = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            existing.insert(asset.localIdentifier)
        }
        return existing
    }

    static func fetchScreenshots() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %ld) != 0",
            Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return array(PHAsset.fetchAssets(with: .image, options: options))
    }

    static func fetchVideos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return array(PHAsset.fetchAssets(with: .video, options: options))
    }

    static func array(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        guard result.count > 0 else { return [] }
        return result.objects(at: IndexSet(integersIn: 0..<result.count))
    }

    /// Looks up file sizes in parallel. Sizes are cached, so reloading is cheap.
    static func sized(_ assets: [PHAsset]) -> [MediaItem] {
        var sizes = [Int64](repeating: 0, count: assets.count)
        sizes.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let buffer = buffer  // each iteration writes a different index
            DispatchQueue.concurrentPerform(iterations: assets.count) { index in
                buffer[index] = SizeCache.shared.size(of: assets[index])
            }
        }
        return zip(assets, sizes).map { MediaItem(asset: $0, size: $1) }
    }

    /// Total bytes of every file behind an asset (original, edits, Live Photo video).
    /// Deleting the asset frees all of them.
    static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(0) { total, resource in
            total + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }
}

/// Thread-safe cache of asset sizes, keyed by asset and last edit date.
nonisolated final class SizeCache: @unchecked Sendable {
    static let shared = SizeCache()

    private var sizes: [String: Int64] = [:]
    private let lock = NSLock()

    func size(of asset: PHAsset) -> Int64 {
        let key = "\(asset.localIdentifier)|\(asset.modificationDate?.timeIntervalSince1970 ?? 0)"
        if let cached = lock.withLock({ sizes[key] }) { return cached }
        let size = PhotoLibrary.fileSize(of: asset)
        lock.withLock { sizes[key] = size }
        return size
    }
}

/// Calls back whenever the photo library changes (including after the user shares more photos).
nonisolated final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let onChange: @MainActor @Sendable () -> Void

    /// Creates and registers the observer off the main thread.
    @concurrent
    static func make(onChange: @escaping @MainActor @Sendable () -> Void) async -> PhotoLibraryObserver {
        PhotoLibraryObserver(onChange: onChange)
    }

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [onChange] in onChange() }
    }
}
