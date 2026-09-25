import Photos
import UIKit

/// How blurry a photo must be to be listed.
nonisolated enum BlurLevel: String, CaseIterable, Identifiable, Sendable {
    case veryBlurry, blurry, soft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veryBlurry: "Only very blurry"
        case .blurry: "Blurry"
        case .soft: "Include slightly soft"
        }
    }

    /// Photos with a blur score below this are listed. Lower scores are blurrier.
    /// Measured on a sharp test pattern (score 510) blurred by a Gaussian of radius σ at 256 px:
    /// σ 1 ≈ 70, σ 1.5 ≈ 36–46, σ 2.5 ≈ 18, σ 5 ≈ 8.
    var threshold: Double {
        switch self {
        case .veryBlurry: 12
        case .blurry: 25
        case .soft: 60
        }
    }

    /// The level that lists the most photos; the scan keeps everything under it.
    static let loosest = BlurLevel.soft
}

/// Decides which photos are blurry. Pure logic, unit tested.
nonisolated enum BlurDetector {
    /// How strong a photo's sharpest edges are: the average of the strongest 0.2% of edge values.
    /// Blur spreads edges out and makes them weaker. Using only the strongest edges means a
    /// sharp photo that is mostly sky or wall still scores as sharp (a small crisp subject on a
    /// plain background scores about 180; with the strongest 1% it would drop to about 50).
    static func score(of image: CGImage) -> Double {
        score(laplacian: SimilarPhotoScanner.laplacian(of: image))
    }

    static func score(laplacian values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let strengths = values.map(abs).sorted(by: >)
        let top = strengths.prefix(max(strengths.count / 500, 1))
        return top.reduce(0, +) / Double(top.count)
    }

    /// Indices of the photos below `threshold`, blurriest first.
    static func blurry(scores: [Double], threshold: Double) -> [Int] {
        scores.indices
            .filter { scores[$0] < threshold }
            .sorted { scores[$0] < scores[$1] }
    }
}

nonisolated struct BlurryPhoto: Identifiable, Hashable, @unchecked Sendable {
    let item: MediaItem
    /// Lower is blurrier.
    let score: Double

    var id: String { item.id }
}

nonisolated struct BlurScanResult: @unchecked Sendable {
    /// Every photo below the loosest threshold, blurriest first.
    let photos: [BlurryPhoto]
    let scannedCount: Int
}

/// Finds blurry photos on the device. Runs in parallel at low priority.
nonisolated enum BlurryPhotoScanner {
    @concurrent
    static func scan(progress: @escaping @MainActor @Sendable (Double) -> Void) async -> BlurScanResult {
        let flag = CancelFlag()
        return await withTaskCancellationHandler {
            run(cancel: flag, progress: progress)
        } onCancel: {
            flag.cancel()
        }
    }

    private static func run(cancel: CancelFlag, progress: @escaping @MainActor @Sendable (Double) -> Void) -> BlurScanResult {
        // Every photo except screenshots (text on a screen isn't blurry in the way photos are).
        let assets = SimilarPhotoScanner.fetchPhotos()
        let count = assets.count
        guard count > 0 else {
            Task { @MainActor in progress(1) }
            return BlurScanResult(photos: [], scannedCount: 0)
        }

        var scores = [Double](repeating: .infinity, count: count)
        let counter = ProgressCounter(total: count, scale: 0.95, report: progress)
        scores.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let buffer = buffer  // each iteration writes its own index
            DispatchQueue.concurrentPerform(iterations: count) { index in
                guard !cancel.isCancelled else { return }
                autoreleasepool {
                    buffer[index] = BlurScoreCache.shared.score(of: assets[index]) ?? .infinity
                }
                counter.increment()
            }
        }
        guard !cancel.isCancelled else { return BlurScanResult(photos: [], scannedCount: 0) }

        let blurry = BlurDetector.blurry(scores: scores, threshold: BlurLevel.loosest.threshold)
        let sized = PhotoLibrary.sized(blurry.map { assets[$0] })
        let photos = zip(sized, blurry).map { BlurryPhoto(item: $0, score: scores[$1]) }
        Task { @MainActor in progress(1) }
        return BlurScanResult(photos: photos, scannedCount: count)
    }
}

/// Blur scores by photo and last edit, so scanning again is quick.
nonisolated final class BlurScoreCache: @unchecked Sendable {
    static let shared = BlurScoreCache()

    private var scores: [String: Double] = [:]
    private let lock = NSLock()

    /// Nil when there is no local copy to look at (for example, only in iCloud).
    func score(of asset: PHAsset) -> Double? {
        let key = "\(asset.localIdentifier)|\(asset.modificationDate?.timeIntervalSince1970 ?? 0)"
        if let cached = lock.withLock({ scores[key] }) { return cached }
        guard let image = SimilarPhotoScanner.thumbnail(for: asset, side: 512, highQuality: true) else { return nil }
        let score = BlurDetector.score(of: image)
        lock.withLock { scores[key] = score }
        return score
    }
}
