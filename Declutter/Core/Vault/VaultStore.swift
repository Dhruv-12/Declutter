import CryptoKit
import Foundation

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
    /// For a Live Photo, the file type of its short video, stored next to the photo.
    /// Nil for still photos (and for vaults made before Live Photos were kept whole).
    var liveVideoUTI: String? = nil

    var isLivePhoto: Bool { liveVideoUTI != nil }
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

    /// A Live Photo's video.
    func liveVideo(_ id: UUID) throws -> Data { try open(file(id, "video")) }

    // MARK: Changing

    @discardableResult
    func add(
        photo: Data, thumbnail: Data, uti: String, takenAt: Date?,
        liveVideo: (data: Data, uti: String)? = nil
    ) throws -> VaultItem {
        let item = VaultItem(
            id: UUID(), takenAt: takenAt, addedAt: .now, uti: uti,
            byteCount: Int64(photo.count + (liveVideo?.data.count ?? 0)),
            liveVideoUTI: liveVideo?.uti
        )
        do {
            try write(photo, to: file(item.id, "photo"))
            try write(thumbnail, to: file(item.id, "thumb"))
            if let liveVideo { try write(liveVideo.data, to: file(item.id, "video")) }
        } catch {
            // Leave nothing half-written behind.
            for kind in ["photo", "thumb", "video"] { try? FileManager.default.removeItem(at: file(item.id, kind)) }
            throw error
        }
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
            for kind in ["photo", "thumb", "video"] { try? FileManager.default.removeItem(at: file(id, kind)) }
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
        // The folder can vanish (for example if the app's storage was cleared); make sure it's there.
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try VaultCrypto.seal(data, with: key).write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func open(_ url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.notFound }
        return try VaultCrypto.open(Data(contentsOf: url), with: key)
    }
}

