import AVFoundation
import Foundation
import Photos
import Testing
@testable import Declutter

@Suite("Video compression math")
@MainActor
struct CompressionMathTests {
    @Test func savingOnlyCountsWhenTheCopyIsWorthKeeping() {
        #expect(CompressionMath.saving(original: 100_000_000, copy: 40_000_000) == 60_000_000)
        #expect(CompressionMath.saving(original: 100_000_000, copy: 90_000_000) == 10_000_000)
        #expect(CompressionMath.saving(original: 100_000_000, copy: 95_000_000) == nil, "Under 10% isn't worth it")
        #expect(CompressionMath.saving(original: 100_000_000, copy: 120_000_000) == nil, "A bigger copy saves nothing")
        #expect(CompressionMath.saving(original: 0, copy: 0) == nil)
    }

    @Test func qualitiesUseDistinctPresets() {
        let presets = CompressionQuality.allCases.map(\.preset)
        #expect(Set(presets).count == presets.count)
        #expect(CompressionQuality.allCases.first == .high)
    }

    @Test func spaceIsOnlySavedOnceTheOriginalIsDeleted() {
        let model = CompressVideosModel()
        model.add(CompressionRecord(originalID: "a", copyID: "a2", originalBytes: 100, copyBytes: 30))
        model.add(CompressionRecord(originalID: "b", copyID: "b2", originalBytes: 50, copyBytes: 20))
        #expect(model.totalSaved == 0)
        #expect(model.copyIDs == ["a2", "b2"])

        model.remove(["a"])
        #expect(model.totalSaved == 70)

        // Deleting a copy forgets that compression.
        model.remove(["b2"])
        #expect(model.records.map(\.copyID) == ["a2"])
        #expect(model.totalSaved == 70)
    }
}

/// Compresses a real seeded video on the simulator. Skipped without Photos access.
@Suite("Video compression (seeded simulator)", .serialized,
       .enabled(if: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Needs Photos access"))
struct VideoCompressorTests {
    private func largestVideo() throws -> PHAsset {
        let videos = PhotoLibrary.fetchVideos().sorted { PhotoLibrary.fileSize(of: $0) > PhotoLibrary.fileSize(of: $1) }
        return try #require(videos.first, "Needs seeded videos")
    }

    @Test func offersQualitiesWithEstimates() async throws {
        let source = try #require(await VideoCompressor.load(try largestVideo()))
        let options = await VideoCompressor.options(for: source)
        #expect(options.contains { $0.quality == .small }, "The 540p quality works everywhere")
        #expect(options.map(\.quality) == CompressionQuality.allCases.filter { quality in options.contains { $0.quality == quality } },
                "Options keep their order")
    }

    @Test func compressesToASmallerCopyAndSavesItToPhotos() async throws {
        let original = try largestVideo()
        let originalBytes = PhotoLibrary.fileSize(of: original)
        let source = try #require(await VideoCompressor.load(original))

        let url = try await VideoCompressor.export(source, quality: .small) { _ in }
        let copyBytes = VideoCompressor.fileSize(url)
        #expect(copyBytes > 0)
        #expect(copyBytes < originalBytes, "copy \(copyBytes) vs original \(originalBytes)")

        let copyID = try await VideoCompressor.saveToPhotos(url, like: original)
        let copy = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [copyID], options: nil).firstObject)
        #expect(copy.mediaType == .video)
        #expect(copy.creationDate == original.creationDate)
        #expect(!FileManager.default.fileExists(atPath: url.path), "The temporary file moves into Photos")
    }
}
