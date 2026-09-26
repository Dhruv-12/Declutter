import ImageIO
import OSLog
import Photos
import UIKit
import UniformTypeIdentifiers

/// Why one photo couldn't be moved into the vault. Each case says which step failed.
nonisolated enum VaultImportError: Error, Equatable, Sendable {
    /// Downloading the photo from iCloud failed.
    case iCloudDownload(domain: String, code: Int, detail: String)
    /// Photos returned no file. `inCloud` is true when the photo only exists in iCloud.
    case noData(inCloud: Bool)
    /// The file couldn't be decoded to make a preview.
    case unreadableFormat(uti: String)
    /// A Live Photo's video couldn't be copied, so the photo wasn't moved (deleting the original
    /// would lose the motion).
    case liveVideo(detail: String)
    /// Encrypting or writing into the vault failed.
    case save(detail: String)
    case cancelled

    /// A plain explanation for the person using the app.
    var message: String {
        switch self {
        case .iCloudDownload(let domain, let code, let detail):
            if domain == NSURLErrorDomain && code == NSURLErrorNotConnectedToInternet {
                return "It's stored in iCloud and your iPhone is offline. Connect to the internet and try again."
            }
            return "It couldn't be downloaded from iCloud (\(detail)). Check your connection and try again."
        case .noData(let inCloud):
            return inCloud
                ? "It's stored in iCloud and didn't download. Check your connection and try again."
                : "Photos didn't hand over this photo's file."
        case .unreadableFormat(let uti):
            return "Its file type (\(uti)) couldn't be read."
        case .liveVideo(let detail):
            return "It's a Live Photo and its video couldn't be copied (\(detail)), so it wasn't moved."
        case .save(let detail):
            return "It couldn't be saved in the vault: \(detail)"
        case .cancelled:
            return "Its download was cancelled."
        }
    }

    /// For the log: the step that failed.
    var step: String {
        switch self {
        case .iCloudDownload: "icloud-download"
        case .noData: "no-data"
        case .unreadableFormat: "preview"
        case .liveVideo: "live-video"
        case .save: "save"
        case .cancelled: "cancelled"
        }
    }
}

nonisolated struct VaultImportFailure: Identifiable, Equatable, Sendable {
    /// The photo's Photos identifier.
    let id: String
    let takenAt: Date?
    let error: VaultImportError

    var label: String {
        takenAt.map { "Photo from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Photo"
    }
}

nonisolated struct VaultImportResult: @unchecked Sendable {
    /// Originals that are safely in the vault; only these may be offered for deletion.
    let copied: [PHAsset]
    let failures: [VaultImportFailure]
}

nonisolated struct VaultImportProgress: Equatable, Sendable {
    /// 1-based photo being worked on.
    let current: Int
    let total: Int
    /// 0...1 while the photo downloads from iCloud; nil once it's local.
    let download: Double?

    var text: String {
        if let download, download < 1 {
            return "Downloading photo \(current) of \(total) from iCloud… \(Int(download * 100))%"
        }
        return "Encrypting photo \(current) of \(total)…"
    }
}

/// Moves photos between Photos and the vault. Everything stays on this iPhone; photos kept only
/// in iCloud are downloaded from Apple's iCloud first, as the Photos app does.
nonisolated enum VaultTransfer {
    static let logger = Logger(subsystem: "com.dhruv.Declutter", category: "Vault")

    enum Failure: LocalizedError {
        case notSaved(String)

        var errorDescription: String? {
            switch self {
            case .notSaved(let detail): "The photos couldn't be saved to Photos: \(detail)"
            }
        }
    }

    // MARK: Into the vault

    /// Copies each photo's current version (and a Live Photo's video) into the vault. Photos that
    /// fail are reported one by one with the reason; the rest are added.
    @concurrent
    static func copyIn(
        _ assets: [PHAsset],
        to store: VaultStore,
        progress: @escaping @MainActor @Sendable (VaultImportProgress) -> Void = { _ in }
    ) async -> VaultImportResult {
        var copied: [PHAsset] = []
        var failures: [VaultImportFailure] = []

        for (index, asset) in assets.enumerated() {
            let current = index + 1
            let report: @Sendable (Double?) -> Void = { download in
                let update = VaultImportProgress(current: current, total: assets.count, download: download)
                Task { @MainActor in progress(update) }
            }
            report(nil)
            do {
                let (data, uti) = try await imageData(for: asset) { report($0) }
                report(nil)
                guard let thumbnail = makeThumbnail(from: data) else {
                    throw VaultImportError.unreadableFormat(uti: uti)
                }
                var video: (data: Data, uti: String)?
                if asset.mediaSubtypes.contains(.photoLive) {
                    video = try await liveVideo(for: asset)
                }
                do {
                    try store.add(photo: data, thumbnail: thumbnail, uti: uti, takenAt: asset.creationDate, liveVideo: video)
                } catch {
                    throw VaultImportError.save(detail: describe(error))
                }
                copied.append(asset)
            } catch {
                let reason = error as? VaultImportError ?? .save(detail: describe(error))
                failures.append(VaultImportFailure(id: asset.localIdentifier, takenAt: asset.creationDate, error: reason))
                logger.error("""
                    Vault import failed at \(reason.step, privacy: .public) for \(asset.localIdentifier, privacy: .private): \
                    \(String(describing: reason), privacy: .public)
                    """)
            }
        }
        return VaultImportResult(copied: copied, failures: failures)
    }

    /// The photo's current version, downloading it from iCloud if needed.
    private static func imageData(
        for asset: PHAsset,
        onDownload: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, String) {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { fraction, _, _, _ in onDownload(fraction) }

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                if let error = info?[PHImageErrorKey] as? NSError {
                    continuation.resume(throwing: VaultImportError.iCloudDownload(
                        domain: error.domain, code: error.code, detail: error.localizedDescription))
                } else if (info?[PHImageCancelledKey] as? Bool) == true {
                    continuation.resume(throwing: VaultImportError.cancelled)
                } else if let data {
                    continuation.resume(returning: (data, uti ?? UTType.jpeg.identifier))
                } else {
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                    continuation.resume(throwing: VaultImportError.noData(inCloud: inCloud))
                }
            }
        }
    }

    /// A Live Photo's video: the edited one if the photo was edited, otherwise the original.
    private static func liveVideo(for asset: PHAsset) async throws -> (data: Data, uti: String) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo })
        else { throw VaultImportError.liveVideo(detail: "the video part wasn't found") }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let buffer = DataBuffer()
        return try await withCheckedThrowingContinuation { continuation in
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                buffer.append(chunk)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: VaultImportError.liveVideo(detail: describe(error)))
                } else {
                    continuation.resume(returning: (buffer.data, resource.uniformTypeIdentifier))
                }
            }
        }
    }

    /// A small JPEG preview. ImageIO reads HEIC, JPEG, PNG and RAW, respects rotation, and doesn't
    /// decode the full image to do it.
    static func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }

    // MARK: Back to Photos

    /// Adds vault photos back to Photos with their original dates; Live Photos come back live.
    /// They stay in the vault.
    @concurrent
    static func saveToPhotos(_ items: [VaultItem], from store: VaultStore) async throws {
        let files = try items.map { item in
            (item: item,
             photo: try store.photo(item.id),
             video: item.isLivePhoto ? try? store.liveVideo(item.id) : nil)
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for file in files {
                    let request = PHAssetCreationRequest.forAsset()
                    let photoOptions = PHAssetResourceCreationOptions()
                    photoOptions.uniformTypeIdentifier = file.item.uti
                    request.addResource(with: .photo, data: file.photo, options: photoOptions)
                    if let video = file.video, let videoUTI = file.item.liveVideoUTI {
                        let videoOptions = PHAssetResourceCreationOptions()
                        videoOptions.uniformTypeIdentifier = videoUTI
                        request.addResource(with: .pairedVideo, data: video, options: videoOptions)
                    }
                    request.creationDate = file.item.takenAt
                }
            }
        } catch {
            logger.error("Saving vault photos to Photos failed: \(describe(error), privacy: .public)")
            throw Failure.notSaved(error.localizedDescription)
        }
    }

    /// "Domain code: description", for messages and the log.
    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.localizedDescription) [\(error.domain) \(error.code)]"
    }
}

/// Collects a file's bytes as they arrive from Photos.
private nonisolated final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data { lock.withLock { storage } }

    func append(_ chunk: Data) { lock.withLock { storage.append(chunk) } }
}
