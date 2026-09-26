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

nonisolated enum SizeMath {
    /// Total size with each id counted once, for totals that combine several lists.
    static func uniqueTotal(_ items: [(id: String, bytes: Int64)]) -> Int64 {
        var seen = Set<String>()
        return items.reduce(0) { total, item in
            seen.insert(item.id).inserted ? total + item.bytes : total
        }
    }
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

    /// The size the Photos app shows for an asset. Every size in Declutter comes from here.
    static func fileSize(of asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset).map { resource in
            AssetSize.Resource(type: resource.type, bytes: (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
        return AssetSize.bytes(of: resources)
    }
}

/// Picks which of an asset's files count toward its size, so sizes match the Photos app.
/// Pure logic, unit tested.
///
/// An asset can have several files: the original, an edited version, the edit instructions,
/// and for a Live Photo a short video. Photos shows the size of the current version only:
/// - Video: the edited video if there is one, otherwise the original.
/// - Photo: the edited photo if there is one, otherwise the original.
/// - Live Photo: that photo plus its video (edited if there is one), counted once.
nonisolated enum AssetSize {
    struct Resource: Equatable {
        let type: PHAssetResourceType
        let bytes: Int64
    }

    static func bytes(of resources: [Resource]) -> Int64 {
        func size(_ type: PHAssetResourceType) -> Int64? {
            resources.first { $0.type == type }?.bytes
        }

        if let video = size(.fullSizeVideo) ?? size(.video) {
            return video
        }
        if let photo = size(.fullSizePhoto) ?? size(.photo) {
            let pairedVideo = size(.fullSizePairedVideo) ?? size(.pairedVideo) ?? 0
            return photo + pairedVideo
        }
        // Anything else (for example a RAW-only photo): its biggest file.
        return resources.map(\.bytes).max() ?? 0
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
