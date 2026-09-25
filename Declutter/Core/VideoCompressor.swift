import AVFoundation
import Photos

/// How much to shrink a video.
nonisolated enum CompressionQuality: String, CaseIterable, Identifiable, Sendable {
    case high, balanced, small

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: "High quality"
        case .balanced: "Balanced"
        case .small: "Smallest"
        }
    }

    var detail: String {
        switch self {
        case .high: "Up to 1080p, efficient HEVC. Best for 4K videos."
        case .balanced: "Up to 720p. Good on a phone screen."
        case .small: "Up to 540p. For sharing and keepsakes."
        }
    }

    var preset: String {
        switch self {
        case .high: AVAssetExportPresetHEVC1920x1080
        case .balanced: AVAssetExportPreset1280x720
        case .small: AVAssetExportPreset960x540
        }
    }
}

/// Space arithmetic for compression. Pure logic, unit tested.
nonisolated enum CompressionMath {
    /// Space saved by keeping the copy instead of the original, or nil when it isn't worth it
    /// (the copy would be less than 10% smaller).
    static func saving(original: Int64, copy: Int64) -> Int64? {
        let saved = original - copy
        guard saved > 0, Double(saved) >= Double(original) * 0.1 else { return nil }
        return saved
    }
}

/// A quality the video can be compressed to, with the expected size when iOS can estimate it.
nonisolated struct CompressionOption: Identifiable, Hashable, Sendable {
    let quality: CompressionQuality
    let estimatedBytes: Int64?

    var id: String { quality.id }
}

/// An AVAsset passed between threads. AVAsset is safe to read from any thread.
nonisolated struct VideoSource: @unchecked Sendable {
    let asset: AVAsset
}

enum CompressionError: LocalizedError {
    case unavailable
    case exportFailed(String?)
    case notSaved

    var errorDescription: String? {
        switch self {
        case .unavailable: "This video couldn't be opened. If it's in iCloud, check your connection and try again."
        case .exportFailed(let reason): reason ?? "The video couldn't be compressed."
        case .notSaved: "The smaller copy couldn't be saved to Photos."
        }
    }
}

/// Makes a smaller copy of a video and saves it to Photos. Everything happens on the device.
nonisolated enum VideoCompressor {
    /// Opens the video's original file (downloading it from iCloud if needed).
    @concurrent
    static func load(_ asset: PHAsset) async -> VideoSource? {
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                continuation.resume(returning: avAsset.map(VideoSource.init))
            }
        }
    }

    /// The qualities this device can produce for the video, with size estimates.
    @concurrent
    static func options(for source: VideoSource) async -> [CompressionOption] {
        var result: [CompressionOption] = []
        for quality in CompressionQuality.allCases {
            guard await AVAssetExportSession.compatibility(ofExportPreset: quality.preset, with: source.asset, outputFileType: .mp4),
                  let session = AVAssetExportSession(asset: source.asset, presetName: quality.preset)
            else { continue }
            session.outputFileType = .mp4
            let estimate = try? await session.estimatedOutputFileLengthInBytes
            result.append(CompressionOption(quality: quality, estimatedBytes: estimate.flatMap { $0 > 0 ? $0 : nil }))
        }
        return result
    }

    /// Writes a compressed copy to a temporary file and returns it.
    @concurrent
    static func export(
        _ source: VideoSource,
        quality: CompressionQuality,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let session = AVAssetExportSession(asset: source.asset, presetName: quality.preset) else {
            throw CompressionError.exportFailed(nil)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Declutter-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        session.shouldOptimizeForNetworkUse = true

        if #available(iOS 18.0, *) {
            let watcher = Task {
                for await state in session.states(updateInterval: 0.2) {
                    if case .exporting(let exportProgress) = state {
                        let fraction = exportProgress.fractionCompleted
                        await MainActor.run { progress(fraction) }
                    }
                }
            }
            defer { watcher.cancel() }
            do {
                try await session.export(to: url, as: .mp4)
            } catch {
                throw CompressionError.exportFailed(error.localizedDescription)
            }
        } else {
            session.outputURL = url
            session.outputFileType = .mp4
            session.exportAsynchronously {}
            while session.status == .waiting || session.status == .exporting || session.status == .unknown {
                if Task.isCancelled { session.cancelExport() }
                let fraction = Double(session.progress)
                await MainActor.run { progress(fraction) }
                try? await Task.sleep(for: .milliseconds(200))
            }
            try Task.checkCancellation()
            guard session.status == .completed else {
                throw CompressionError.exportFailed(session.error?.localizedDescription)
            }
        }
        await MainActor.run { progress(1) }
        return url
    }

    /// Adds the copy to Photos with the original's date, place and favourite, and returns its id.
    /// The temporary file is moved into the library.
    @concurrent
    static func saveToPhotos(_ url: URL, like original: PHAsset) async throws -> String {
        let date = original.creationDate
        let location = original.location
        let favorite = original.isFavorite
        let created = CreatedID()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .video, fileURL: url, options: options)
                request.creationDate = date
                request.location = location
                request.isFavorite = favorite
                created.id = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw CompressionError.notSaved
        }
        guard let id = created.id else { throw CompressionError.notSaved }
        return id
    }

    static func fileSize(_ url: URL) -> Int64 {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
        return size ?? 0
    }
}

/// Carries the new asset's id out of the Photos change block.
private nonisolated final class CreatedID: @unchecked Sendable {
    var id: String?
}
