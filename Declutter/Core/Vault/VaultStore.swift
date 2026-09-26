import CryptoKit
import Foundation
import Photos
import UIKit

/// A photo in the vault. Only this summary is kept alongside the encrypted files, and it is
/// encrypted too.
nonisolated struct VaultItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// When the photo was taken, so it goes back to the same place in Photos.
    let takenAt: Date?
    let addedAt: Date
    /// File type of the original, such as public.heic or public.jpeg.
    let uti: String
    let byteCount: Int64
}

/// The vault's files: each photo and a small preview, encrypted with AES-GCM, plus an encrypted
/// index. Stored in the app's own folder with the strongest file protection and left out of
/// backups, so vault photos never leave this iPhone.
nonisolated final class VaultStore: @unchecked Sendable {
    let directory: URL
    private let key: SymmetricKey
    private let lock = NSLock()

    enum Failure: LocalizedError {
        case notFound

        var errorDescription: String? { "This photo isn't in the vault any more." }
    }

    /// The real vault on this device.
    static func onDevice() throws -> VaultStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try VaultStore(directory: support.appendingPathComponent("Vault", isDirectory: true), key: VaultCrypto.deviceKey())
    }

    init(directory: URL, key: SymmetricKey) throws {
        self.directory = directory
        self.key = key
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    // MARK: Reading

    /// Newest photos first.
    func items() throws -> [VaultItem] {
        try lock.withLock { try readIndex() }
            .sorted { ($0.takenAt ?? $0.addedAt) > ($1.takenAt ?? $1.addedAt) }
    }

    func photo(_ id: UUID) throws -> Data { try open(file(id, "photo")) }

    func thumbnail(_ id: UUID) throws -> Data { try open(file(id, "thumb")) }

    // MARK: Changing

    @discardableResult
    func add(photo: Data, thumbnail: Data, uti: String, takenAt: Date?) throws -> VaultItem {
        let item = VaultItem(id: UUID(), takenAt: takenAt, addedAt: .now, uti: uti, byteCount: Int64(photo.count))
        try write(photo, to: file(item.id, "photo"))
        try write(thumbnail, to: file(item.id, "thumb"))
        try lock.withLock {
            var index = try readIndex()
            index.append(item)
            try writeIndex(index)
        }
        return item
    }

    /// Permanently removes photos from the vault.
    func delete(_ ids: Set<UUID>) throws {
        try lock.withLock {
            let index = try readIndex()
            try writeIndex(index.filter { !ids.contains($0.id) })
        }
        for id in ids {
            try? FileManager.default.removeItem(at: file(id, "photo"))
            try? FileManager.default.removeItem(at: file(id, "thumb"))
        }
    }

    // MARK: Files

    private var indexFile: URL { directory.appendingPathComponent("index") }

    private func file(_ id: UUID, _ kind: String) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(kind)")
    }

    private func readIndex() throws -> [VaultItem] {
        guard FileManager.default.fileExists(atPath: indexFile.path) else { return [] }
        return try JSONDecoder().decode([VaultItem].self, from: open(indexFile))
    }

    private func writeIndex(_ items: [VaultItem]) throws {
        try write(JSONEncoder().encode(items), to: indexFile)
    }

    private func write(_ data: Data, to url: URL) throws {
        try VaultCrypto.seal(data, with: key).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func open(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.notFound }
        return try VaultCrypto.open(Data(contentsOf: url), with: key)
    }
}

/// Moves photos between Photos and the vault. Everything stays on this iPhone.
nonisolated enum VaultTransfer {
    enum Failure: LocalizedError {
        case notSaved

        var errorDescription: String? { "The photos couldn't be saved to Photos." }
    }

    /// Copies each photo's current version into the vault. Returns how many made it in and the
    /// originals that did (so they can be offered for deletion).
    @concurrent
    static func copyIn(_ assets: [PHAsset], to store: VaultStore) async -> (copied: [PHAsset], failed: Int) {
        var copied: [PHAsset] = []
        for asset in assets {
            guard let (data, uti) = await imageData(for: asset),
                  let thumbnail = makeThumbnail(from: data)
            else { continue }
            if (try? store.add(photo: data, thumbnail: thumbnail, uti: uti, takenAt: asset.creationDate)) != nil {
                copied.append(asset)
            }
        }
        return (copied, assets.count - copied.count)
    }

    /// Adds vault photos back to Photos with their original dates. They stay in the vault.
    @concurrent
    static func saveToPhotos(_ items: [VaultItem], from store: VaultStore) async throws {
        let photos = try items.map { (item: $0, data: try store.photo($0.id)) }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                for (item, data) in photos {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = item.uti
                    request.addResource(with: .photo, data: data, options: options)
                    request.creationDate = item.takenAt
                }
            }
        } catch {
            throw Failure.notSaved
        }
    }

    private static func imageData(for asset: PHAsset) async -> (Data, String)? {
        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else { return continuation.resume(returning: nil) }
                continuation.resume(returning: (data, uti ?? "public.jpeg"))
            }
        }
    }

    static func makeThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data),
              let small = image.preparingThumbnail(of: CGSize(width: 400, height: 400 * image.size.height / max(image.size.width, 1)))
        else { return nil }
        return small.jpegData(compressionQuality: 0.8)
    }
}
