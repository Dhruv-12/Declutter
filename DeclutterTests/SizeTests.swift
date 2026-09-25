import Foundation
import Photos
import Testing
@testable import Declutter

@Suite("Size calculations")
@MainActor
struct SizeTests {
    @Test func byteFormatting() {
        #expect(ByteFormat.string(1_000_000) == "1 MB")
        #expect(ByteFormat.string(1_200_000_000) == "1.2 GB")
        #expect(!ByteFormat.string(0).isEmpty)
    }

    @Test func deviceStorageMath() {
        let storage = DeviceStorage(total: 128_000_000_000, available: 32_000_000_000)
        #expect(storage.used == 96_000_000_000)
        #expect(storage.usedFraction == 0.75)
        #expect(DeviceStorage(total: 0, available: 0).usedFraction == 0)
        #expect(DeviceStorage(total: 10, available: 20).used == 0)
    }

    @Test func storageBarAddsUpToUsedSpace() {
        let storage = DeviceStorage(total: 100, available: 40)
        let breakdown = StorageBreakdown(storage: storage, cleanable: 15, freed: 5)
        #expect(breakdown.freed == 5)
        #expect(breakdown.cleanable == 15)
        #expect(breakdown.otherUsed == 40)
        #expect(breakdown.freed + breakdown.cleanable + breakdown.otherUsed == storage.used)
    }

    @Test func storageBarNeverShowsMoreThanIsUsed() {
        let storage = DeviceStorage(total: 100, available: 40)
        let tooMuch = StorageBreakdown(storage: storage, cleanable: 500, freed: 20)
        #expect(tooMuch.cleanable == 40)
        #expect(tooMuch.otherUsed == 0)
        let negative = StorageBreakdown(storage: storage, cleanable: -5, freed: -5)
        #expect(negative.cleanable == 0 && negative.freed == 0 && negative.otherUsed == 60)
    }

    @Test func videoSizeFilters() {
        #expect(SizeFilter.all.bytes == 0)
        #expect(SizeFilter.over50MB.bytes == 50_000_000)
        #expect(SizeFilter.over500MB.bytes == 500_000_000)
        #expect(SizeFilter.over100MB.title == "Over 100 MB")
    }

    @Test func cleanupTotals() {
        let result = CleanupResult(photosDeleted: 3, videosDeleted: 2, contactsDeleted: 1, bytesFreed: 42)
        #expect(result.totalItems == 6)
    }
}

/// Runs against the simulator's real photo library (seeded by Scripts/run-tests.sh).
/// Skipped when there is no Photos access or nothing to measure.
@Suite("Photo library sizes (seeded simulator)",
       .enabled(if: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Needs Photos access"))
struct PhotoLibrarySizeTests {
    @Test func dashboardMediaIsSizedAndSortedLargestFirst() async throws {
        let media = await PhotoLibrary.loadDashboardMedia()
        try #require(!media.videos.isEmpty, "Needs seeded videos")

        #expect(media.videos.allSatisfy { $0.size > 0 })
        #expect(media.screenshots.allSatisfy { $0.size > 0 })
        #expect(zip(media.videos, media.videos.dropFirst()).allSatisfy { $0.size >= $1.size })
        #expect(media.videos.totalSize == media.videos.reduce(0) { $0 + $1.size })
    }

    /// The similar and blurry scans look at every photo except screenshots.
    @Test func scansSeeEveryPhotoExceptScreenshots() throws {
        let screenshots = PhotoLibrary.fetchScreenshots()
        try #require(!screenshots.isEmpty, "Needs seeded screenshots")
        let allImages = PHAsset.fetchAssets(with: .image, options: nil).count
        let photos = SimilarPhotoScanner.fetchPhotos()
        #expect(!photos.isEmpty)
        #expect(photos.count == allImages - screenshots.count)
        #expect(photos.allSatisfy { !$0.mediaSubtypes.contains(.photoScreenshot) })
    }

    @Test func sizeCacheMatchesDirectLookup() throws {
        let videos = PhotoLibrary.fetchVideos()
        try #require(!videos.isEmpty, "Needs seeded videos")
        for asset in videos.prefix(3) {
            #expect(SizeCache.shared.size(of: asset) == PhotoLibrary.fileSize(of: asset))
        }
    }
}
