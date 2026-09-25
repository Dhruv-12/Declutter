import CoreML
import Photos
import UIKit
import Vision

/// A set of photos that look alike. One of them is marked as the best one to keep.
nonisolated struct SimilarGroup: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    /// Oldest first.
    let items: [MediaItem]
    var bestID: String

    var extras: [MediaItem] { items.filter { $0.id != bestID } }
    var date: Date? { items.first?.asset.creationDate }
}

nonisolated enum MatchStrictness: String, CaseIterable, Identifiable, Sendable {
    case strict, balanced, loose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strict: "Near-identical only"
        case .balanced: "Balanced"
        case .loose: "Loosely similar"
        }
    }

    /// Maximum Vision feature print distance for two photos to count as similar.
    var threshold: Float {
        switch self {
        case .strict: 0.30
        case .balanced: 0.45
        case .loose: 0.60
        }
    }
}

nonisolated struct SimilarScanResult: @unchecked Sendable {
    let groups: [SimilarGroup]
    let scannedCount: Int
}

/// Finds duplicate and near-identical photos entirely on the device.
///
/// Fast on large libraries because it never compares every photo with every other photo:
/// 1. Similar shots are almost always taken close together, so each photo is only compared
///    with a few photos taken just before it (within `timeWindow`).
/// 2. Exact duplicates can be taken at any time (saved twice, re-imported), so every photo gets
///    a tiny 64-bit fingerprint and matching fingerprints are grouped with a dictionary.
/// 3. Thumbnails are small cached images and the work runs in parallel on every CPU core.
nonisolated enum SimilarPhotoScanner {
    static let timeWindow: TimeInterval = 120
    static let neighboursToCompare = 6
    /// Duplicates found by fingerprint must also pass this stricter Vision check.
    static let duplicateThreshold: Float = 0.30

    @concurrent
    static func scan(
        strictness: MatchStrictness,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async -> SimilarScanResult {
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            run(strictness: strictness, cancel: flag, progress: progress)
        } onCancel: {
            flag.cancel()
        }
    }

    private static func run(
        strictness: MatchStrictness,
        cancel: CancelFlag,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) -> SimilarScanResult {
        let assets = fetchPhotos()
        let count = assets.count
        guard count > 1 else { return SimilarScanResult(groups: [], scannedCount: count) }

        // 1. Mark photos that have another photo taken shortly before or after them.
        let inBurst = SimilarGrouping.burstFlags(assets.map(\.creationDate))

        // 2. Fingerprint every photo; Vision feature prints only where there is something to compare.
        var hashes = [UInt64](repeating: 0, count: count)
        var prints = [VNFeaturePrintObservation?](repeating: nil, count: count)
        let counter = ProgressCounter(total: count, scale: 0.9, report: progress)
        let burstFlags = inBurst

        hashes.withUnsafeMutableBufferPointer { hashBuffer in
            prints.withUnsafeMutableBufferPointer { printBuffer in
                // Each iteration writes only its own index, so parallel writes never overlap.
                nonisolated(unsafe) let hashBuffer = hashBuffer
                nonisolated(unsafe) let printBuffer = printBuffer
                DispatchQueue.concurrentPerform(iterations: count) { index in
                    guard !cancel.isCancelled else { return }
                    autoreleasepool {
                        if let image = thumbnail(for: assets[index], side: 300) {
                            hashBuffer[index] = differenceHash(of: image)
                            if burstFlags[index] {
                                printBuffer[index] = featurePrint(of: image)
                            }
                        }
                    }
                    counter.increment()
                }
            }
        }
        guard !cancel.isCancelled else { return SimilarScanResult(groups: [], scannedCount: 0) }

        // 3–4. Group them (see `SimilarGrouping`, which is unit tested).
        let fingerprints = (0..<count).map { index in
            PhotoFingerprint(
                date: assets[index].creationDate,
                hash: hashes[index],
                shape: SimilarGrouping.shape(width: assets[index].pixelWidth, height: assets[index].pixelHeight),
                print: prints[index]
            )
        }
        let groupIndices = SimilarGrouping.group(
            fingerprints,
            threshold: strictness.threshold,
            distance: distance,
            // Confirm fingerprint matches with Vision, computing a print if the photo doesn't have one.
            printFor: { thumbnail(for: assets[$0], side: 300).flatMap(featurePrint) }
        )
        guard !groupIndices.isEmpty, !cancel.isCancelled else {
            Task { @MainActor in progress(1) }
            return SimilarScanResult(groups: [], scannedCount: count)
        }

        // 5. Look up sizes and quality only for photos that ended up in a group.
        let flat = groupIndices.flatMap { $0 }
        let sized = PhotoLibrary.sized(flat.map { assets[$0] })
        let qualities = qualityScores(for: flat.map { assets[$0] })
        var itemFor: [Int: (MediaItem, PhotoQuality)] = [:]
        for (position, index) in flat.enumerated() {
            itemFor[index] = (sized[position], qualities[position])
        }

        let result = groupIndices.map { indices -> SimilarGroup in
            let entries = indices.compactMap { itemFor[$0] }
            let items = entries.map(\.0)
            let best = BestPhotoPicker.bestIndex(entries.map(\.1))
            return SimilarGroup(id: items[0].id, items: items, bestID: items[best].id)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        Task { @MainActor in progress(1) }
        return SimilarScanResult(groups: result, scannedCount: count)
    }

    // MARK: - Fetching

    /// Every photo except screenshots (those have their own screen), oldest first.
    static func fetchPhotos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtypes & %ld) == 0",
            Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return PhotoLibrary.array(PHAsset.fetchAssets(with: .image, options: options))
    }

    /// Small image from the on-device cache. Never downloads from iCloud.
    static func thumbnail(for asset: PHAsset, side: CGFloat, highQuality: Bool = false) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = highQuality ? .highQualityFormat : .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    // MARK: - Fingerprints

    /// Vision's description of what the image looks like. Close prints mean similar pictures.
    static func featurePrint(of image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        perform(request, on: image)
        return request.results?.first
    }

    /// Runs a Vision request. If it fails (the simulator can't use the GPU or Neural Engine for
    /// these requests, and a busy device can refuse too), it tries again on the CPU.
    private static func perform(_ request: VNRequest, on image: CGImage) {
        if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil { return }
        let cpu = MLComputeDevice.allComputeDevices.first { device in
            if case .cpu = device { return true }
            return false
        }
        for stage in ((try? request.supportedComputeStageDevices) ?? [:]).keys {
            request.setComputeDevice(cpu, for: stage)
        }
        try? VNImageRequestHandler(cgImage: image).perform([request])
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        var value = Float.greatestFiniteMagnitude
        try? a.computeDistance(&value, to: b)
        return value
    }

    /// 64-bit "difference hash": shrink to 9×8 grey pixels and record whether each pixel
    /// is brighter than its right-hand neighbour. Identical images give identical hashes.
    static func differenceHash(of image: CGImage) -> UInt64 {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }

        var hash: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                hash <<= 1
                if pixels[row * width + column] > pixels[row * width + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    // MARK: - Picking the best photo

    private static func qualityScores(for assets: [PHAsset]) -> [PhotoQuality] {
        var scores = [PhotoQuality](repeating: PhotoQuality(), count: assets.count)
        scores.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: assets.count) { index in
                autoreleasepool {
                    buffer[index] = quality(of: assets[index])
                }
            }
        }
        return scores
    }

    private static func quality(of asset: PHAsset) -> PhotoQuality {
        var quality = PhotoQuality()
        quality.isFavorite = asset.isFavorite
        quality.pixels = Double(asset.pixelWidth * asset.pixelHeight)
        guard let image = thumbnail(for: asset, side: 512, highQuality: true) else { return quality }
        quality.sharpness = sharpness(of: image)

        let faces = VNDetectFaceCaptureQualityRequest()
        perform(faces, on: image)
        quality.faceQuality = faces.results?.compactMap { $0.faceCaptureQuality.map(Double.init) }.max()
        return quality
    }

    /// Variance of the Laplacian: blurry images have few sharp edges, so a low value.
    static func sharpness(of image: CGImage) -> Double {
        let values = laplacian(of: image)
        guard !values.isEmpty else { return 0 }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        return values.reduce(0) { $0 + $1 * $1 } / n - mean * mean
    }

    /// Edge strength at every pixel of a 256×256 grey copy (the Laplacian). Sharp edges give
    /// large values; blur spreads edges out and shrinks them. Shared by the best-photo and
    /// blurry-photo checks.
    static func laplacian(of image: CGImage) -> [Double] {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }

        var values: [Double] = []
        values.reserveCapacity((side - 2) * (side - 2))
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let center = Double(pixels[y * side + x]) * 4
                let neighbours = Double(pixels[(y - 1) * side + x]) + Double(pixels[(y + 1) * side + x])
                    + Double(pixels[y * side + x - 1]) + Double(pixels[y * side + x + 1])
                values.append(center - neighbours)
            }
        }
        return values
    }

}

// MARK: - Grouping and best photo (pure logic, unit tested)

/// What grouping needs to know about one photo.
nonisolated struct PhotoFingerprint<Print> {
    var date: Date?
    /// 64-bit difference hash; 0 means it couldn't be computed.
    var hash: UInt64
    /// Short side × long side, so a rotated copy still matches.
    var shape: String
    /// Vision feature print, only computed for photos taken close to another photo.
    var print: Print?
}

nonisolated enum SimilarGrouping {
    static func shape(width: Int, height: Int) -> String {
        "\(min(width, height))x\(max(width, height))"
    }

    /// Which photos (sorted oldest first) have another photo taken within `window` seconds.
    static func burstFlags(_ dates: [Date?], window: TimeInterval = SimilarPhotoScanner.timeWindow) -> [Bool] {
        var flags = [Bool](repeating: false, count: dates.count)
        guard dates.count > 1 else { return flags }
        for index in 1..<dates.count {
            guard let a = dates[index - 1], let b = dates[index], abs(b.timeIntervalSince(a)) <= window else { continue }
            flags[index - 1] = true
            flags[index] = true
        }
        return flags
    }

    /// Groups similar photos. Photos must be sorted oldest first. Returns groups of two or more
    /// indices, each sorted.
    ///
    /// - Similar shots: each photo is compared with up to `neighbours` photos taken just before it,
    ///   within `window` seconds, and joined if their prints are within `threshold`.
    /// - Exact duplicates anywhere: same non-trivial hash and same shape, confirmed by a print
    ///   distance within `duplicateThreshold` (`printFor` supplies prints that weren't computed).
    static func group<Print>(
        _ photos: [PhotoFingerprint<Print>],
        threshold: Float,
        duplicateThreshold: Float = SimilarPhotoScanner.duplicateThreshold,
        window: TimeInterval = SimilarPhotoScanner.timeWindow,
        neighbours: Int = SimilarPhotoScanner.neighboursToCompare,
        distance: (Print, Print) -> Float,
        printFor: (Int) -> Print?
    ) -> [[Int]] {
        let count = photos.count
        guard count > 1 else { return [] }
        var groups = UnionFind(count: count)

        for index in 0..<count {
            guard let current = photos[index].print, let date = photos[index].date else { continue }
            var other = index - 1
            while other >= 0, index - other <= neighbours,
                  let otherDate = photos[other].date,
                  date.timeIntervalSince(otherDate) <= window {
                if let previous = photos[other].print, distance(current, previous) <= threshold {
                    groups.union(index, other)
                }
                other -= 1
            }
        }

        var buckets: [String: [Int]] = [:]
        for index in 0..<count {
            let hash = photos[index].hash
            // All-dark or all-flat images produce trivial fingerprints; skip them.
            guard hash != 0, hash != .max else { continue }
            buckets["\(hash)-\(photos[index].shape)", default: []].append(index)
        }
        for bucket in buckets.values where bucket.count > 1 {
            let first = photos[bucket[0]].print ?? printFor(bucket[0])
            for index in bucket.dropFirst() where groups.find(index) != groups.find(bucket[0]) {
                let other = photos[index].print ?? printFor(index)
                if let first, let other, distance(first, other) <= duplicateThreshold {
                    groups.union(index, bucket[0])
                }
            }
        }

        var members: [Int: [Int]] = [:]
        for index in 0..<count {
            members[groups.find(index), default: []].append(index)
        }
        return members.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}

nonisolated enum BestPhotoPicker {
    /// Index of the photo to keep. Favourites always win. Otherwise sharpness matters most,
    /// then faces (only when the set has any), then resolution.
    static func bestIndex(_ qualities: [PhotoQuality]) -> Int {
        guard !qualities.isEmpty else { return 0 }
        let maxSharpness = max(qualities.map(\.sharpness).max() ?? 1, 1)
        let maxPixels = max(qualities.map(\.pixels).max() ?? 1, 1)
        let hasFaces = qualities.contains { $0.faceQuality != nil }

        func score(_ quality: PhotoQuality) -> Double {
            var score = 0.5 * quality.sharpness / maxSharpness + 0.2 * quality.pixels / maxPixels
            if hasFaces { score += 0.3 * (quality.faceQuality ?? 0) }
            if quality.isFavorite { score += 10 }
            return score
        }
        var best = 0
        for index in qualities.indices where score(qualities[index]) > score(qualities[best]) {
            best = index
        }
        return best
    }
}

nonisolated struct PhotoQuality: Sendable {
    var isFavorite = false
    var pixels = 0.0
    var sharpness = 0.0
    var faceQuality: Double?
}

// MARK: - Helpers

nonisolated struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a), rootB = find(b)
        if rootA != rootB { parent[rootB] = rootA }
    }
}

nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

/// Counts finished photos from many threads and reports progress to the UI about 100 times.
nonisolated final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private let total: Int
    private let scale: Double
    private let step: Int
    private let report: @MainActor @Sendable (Double) -> Void
    private var done = 0

    init(total: Int, scale: Double, report: @escaping @MainActor @Sendable (Double) -> Void) {
        self.total = max(total, 1)
        self.scale = scale
        self.step = max(total / 100, 1)
        self.report = report
    }

    func increment() {
        let value: Int = lock.withLock {
            done += 1
            return done
        }
        guard value % step == 0 || value == total else { return }
        let fraction = Double(value) / Double(total) * scale
        Task { @MainActor [report] in report(fraction) }
    }
}
