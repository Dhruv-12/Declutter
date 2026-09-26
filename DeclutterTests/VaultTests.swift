import CryptoKit
import Foundation
import Photos
import Testing
import UIKit
@testable import Declutter

@Suite("Vault encryption and PIN")
struct VaultSecurityTests {
    @Test func encryptionRoundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let secret = Data("a private photo".utf8)
        let sealed = try VaultCrypto.seal(secret, with: key)
        #expect(sealed != secret)
        #expect(try VaultCrypto.open(sealed, with: key) == secret)
    }

    @Test func tamperedOrWronglyKeyedDataIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var sealed = try VaultCrypto.seal(Data("photo".utf8), with: key)
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, with: SymmetricKey(size: .bits256)) }
        sealed[sealed.count / 2] ^= 0xFF
        #expect(throws: (any Error).self) { try VaultCrypto.open(sealed, with: key) }
    }

    @Test func pinRules() {
        #expect(VaultPIN.isValid("1234"))
        #expect(VaultPIN.isValid("123456"))
        #expect(!VaultPIN.isValid("123"))
        #expect(!VaultPIN.isValid("1234567"))
        #expect(!VaultPIN.isValid("12a4"))
        #expect(!VaultPIN.isValid("١٢٣٤"), "Only 0-9")
    }

    @Test func pinIsStoredOnlyAsASaltedHash() {
        let record = VaultPIN.record(for: "4321")
        #expect(record.count == 48)
        #expect(record.range(of: Data("4321".utf8)) == nil, "The PIN itself is never stored")
        #expect(VaultPIN.matches("4321", record: record))
        #expect(!VaultPIN.matches("4322", record: record))
        #expect(!VaultPIN.matches("4321", record: Data()))
        // The same PIN with a different salt gives a different record.
        #expect(VaultPIN.record(for: "4321") != record)
    }

    @Test func fiveWrongPINsLockForThirtySeconds() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var attempts = PINAttempts()
        for _ in 0..<4 { attempts.recordMiss(at: now) }
        #expect(!attempts.isLocked(at: now))
        attempts.recordMiss(at: now)
        #expect(attempts.isLocked(at: now))
        #expect(attempts.secondsLeft(at: now) == 30)
        #expect(attempts.secondsLeft(at: now.addingTimeInterval(20)) == 10)
        #expect(!attempts.isLocked(at: now.addingTimeInterval(31)))
        attempts.recordSuccess()
        #expect(attempts.misses == 0 && !attempts.isLocked(at: now))
    }
}

@Suite("Vault storage", .serialized)
struct VaultStoreTests {
    private func makeStore(key: SymmetricKey = SymmetricKey(size: .bits256)) throws -> VaultStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VaultTest-\(UUID().uuidString)")
        return try VaultStore(directory: folder, key: key)
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }.jpegData(compressionQuality: 0.9)!
    }

    @Test func addReadAndDelete() throws {
        let store = try makeStore()
        let photo = jpeg()
        let taken = Date(timeIntervalSince1970: 1_700_000_000)
        let item = try store.add(photo: photo, thumbnail: Data("thumb".utf8), uti: "public.jpeg", takenAt: taken)

        #expect(try store.items() == [item])
        #expect(try store.photo(item.id) == photo)
        #expect(try store.thumbnail(item.id) == Data("thumb".utf8))
        #expect(item.byteCount == Int64(photo.count))

        try store.delete([item.id])
        #expect(try store.items().isEmpty)
        #expect(throws: (any Error).self) { try store.photo(item.id) }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).filter { $0 != "index" }
        #expect(leftovers.isEmpty, "Photo files are removed too")
    }

    @Test func filesOnDiskAreEncryptedAndNotBackedUp() throws {
        let store = try makeStore()
        let photo = jpeg()
        let item = try store.add(photo: photo, thumbnail: jpeg(), uti: "public.jpeg", takenAt: nil)
        let onDisk = try Data(contentsOf: store.directory.appendingPathComponent("\(item.id.uuidString).photo"))
        #expect(onDisk != photo)
        #expect(onDisk.range(of: photo.prefix(64)) == nil, "The photo's bytes don't appear on disk")
        let index = try Data(contentsOf: store.directory.appendingPathComponent("index"))
        #expect(index.range(of: Data("public.jpeg".utf8)) == nil, "The index is encrypted too")
        #expect(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func anotherKeyCantReadTheVault() throws {
        let store = try makeStore()
        try store.add(photo: jpeg(), thumbnail: jpeg(), uti: "public.jpeg", takenAt: nil)
        let intruder = try VaultStore(directory: store.directory, key: SymmetricKey(size: .bits256))
        #expect(throws: (any Error).self) { try intruder.items() }
    }

    @Test func thumbnailsAreSmall() throws {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1500)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1500))
        }.jpegData(compressionQuality: 0.9)!
        let thumbnail = try #require(VaultTransfer.makeThumbnail(from: big))
        let image = try #require(UIImage(data: thumbnail))
        #expect(image.size.width * image.scale <= 400.5)
    }
}

/// Moves real seeded photos into a throwaway vault and back to Photos.
@Suite("Vault and Photos (seeded simulator)", .serialized,
       .enabled(if: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Needs Photos access"))
struct VaultTransferTests {
    @Test func copiesPhotosInAndSavesThemBack() async throws {
        let photos = Array(SimilarPhotoScanner.fetchPhotos().prefix(2))
        try #require(photos.count == 2, "Needs seeded photos")
        let store = try VaultStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("VaultTransfer-\(UUID().uuidString)"),
            key: SymmetricKey(size: .bits256)
        )

        let result = await VaultTransfer.copyIn(photos, to: store)
        #expect(result.failed == 0)
        #expect(result.copied.map(\.localIdentifier) == photos.map(\.localIdentifier))
        let items = try store.items()
        #expect(items.count == 2)
        #expect(Set(items.compactMap(\.takenAt)) == Set(photos.compactMap(\.creationDate)))

        let before = PHAsset.fetchAssets(with: .image, options: nil).count
        try await VaultTransfer.saveToPhotos(items, from: store)
        #expect(PHAsset.fetchAssets(with: .image, options: nil).count == before + 2)
    }
}
