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
        var inBurst = [Bool](repeating: false, count: count)
        for index in 1..<count where isClose(assets[index - 1], assets[index]) {
            inBurst[index - 1] = true
            inBurst[index] = true
        }

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

        var groups = UnionFind(count: count)

        // 3a. Similar shots: compare each photo with the few taken just before it.
        for index in 0..<count {
            guard let current = prints[index], let date = assets[index].creationDate else { continue }
            var other = index - 1
            while other >= 0, index - other <= neighboursToCompare,
                  let otherDate = assets[other].creationDate,
                  date.timeIntervalSince(otherDate) <= timeWindow {
                if let previous = prints[other],
                   distance(current, previous) <= strictness.threshold {
                    groups.union(index, other)
                }
                other -= 1
            }
        }

        // 3b. Exact duplicates anywhere in the library: same fingerprint and same shape.
        var buckets: [String: [Int]] = [:]
        for index in 0..<count {
            let hash = hashes[index]
            // All-dark or all-flat images produce trivial fingerprints; skip them.
            guard hash != 0, hash != .max else { continue }
            let asset = assets[index]
            let shape = "\(min(asset.pixelWidth, asset.pixelHeight))x\(max(asset.pixelWidth, asset.pixelHeight))"
            buckets["\(hash)-\(shape)", default: []].append(index)
        }
        for bucket in buckets.values where bucket.count > 1 {
            for index in bucket.dropFirst() where groups.find(index) != groups.find(bucket[0]) {
                // Confirm with Vision so different images that happen to share a fingerprint aren't grouped.
                let first = prints[bucket[0]] ?? thumbnail(for: assets[bucket[0]], side: 300).flatMap(featurePrint)
                let other = prints[index] ?? thumbnail(for: assets[index], side: 300).flatMap(featurePrint)
                if let first, let other, distance(first, other) <= duplicateThreshold {
                    groups.union(index, bucket[0])
                }
            }
        }

        // 4. Collect groups of two or more.
        var members: [Int: [Int]] = [:]
        for index in 0..<count {
            members[groups.find(index), default: []].append(index)
        }
        let groupIndices = members.values.filter { $0.count > 1 }.map { $0.sorted() }
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
            return SimilarGroup(id: items[0].id, items: items, bestID: pickBest(entries))
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

    private static func isClose(_ first: PHAsset, _ second: PHAsset) -> Bool {
        guard let a = first.creationDate, let b = second.creationDate else { return false }
        return abs(b.timeIntervalSince(a)) <= timeWindow
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
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first
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
        try? VNImageRequestHandler(cgImage: image).perform([faces])
        quality.faceQuality = faces.results?.compactMap { $0.faceCaptureQuality.map(Double.init) }.max()
        return quality
    }

    /// Variance of the Laplacian: blurry images have few sharp edges, so a low value.
    static func sharpness(of image: CGImage) -> Double {
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

        var sum = 0.0, sumOfSquares = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let center = Double(pixels[y * side + x]) * 4
                let neighbours = Double(pixels[(y - 1) * side + x]) + Double(pixels[(y + 1) * side + x])
                    + Double(pixels[y * side + x - 1]) + Double(pixels[y * side + x + 1])
                let laplacian = center - neighbours
                sum += laplacian
                sumOfSquares += laplacian * laplacian
            }
        }
        let n = Double((side - 2) * (side - 2))
        let mean = sum / n
        return sumOfSquares / n - mean * mean
    }

    /// Favourites always win. Otherwise sharpness matters most, then faces, then resolution.
    private static func pickBest(_ entries: [(MediaItem, PhotoQuality)]) -> String {
        let maxSharpness = max(entries.map(\.1.sharpness).max() ?? 1, 1)
        let maxPixels = max(entries.map(\.1.pixels).max() ?? 1, 1)
        let hasFaces = entries.contains { $0.1.faceQuality != nil }

        func score(_ quality: PhotoQuality) -> Double {
            var score = 0.5 * quality.sharpness / maxSharpness + 0.2 * quality.pixels / maxPixels
            if hasFaces { score += 0.3 * (quality.faceQuality ?? 0) }
            if quality.isFavorite { score += 10 }
            return score
        }
        return entries.max { score($0.1) < score($1.1) }?.0.id ?? entries[0].0.id
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
