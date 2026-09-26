import Photos
import Testing
@testable import Declutter

@Suite("Asset sizes match the Photos app")
struct AssetSizeTests {
    private func resource(_ type: PHAssetResourceType, _ bytes: Int64) -> AssetSize.Resource {
        AssetSize.Resource(type: type, bytes: bytes)
    }

    @Test func unEditedVideoIsItsVideoFile() {
        #expect(AssetSize.bytes(of: [resource(.video, 707_800_000)]) == 707_800_000)
    }

    @Test func editedVideoCountsOnlyTheCurrentVersion() {
        // A trimmed video keeps the original, the edited copy and the edit instructions.
        // Photos shows the edited copy; adding them all up was what doubled the sizes.
        let resources = [
            resource(.video, 690_000_000),
            resource(.fullSizeVideo, 707_800_000),
            resource(.adjustmentData, 2_000),
        ]
        #expect(AssetSize.bytes(of: resources) == 707_800_000)
    }

    @Test func unEditedPhotoIsItsPhotoFile() {
        #expect(AssetSize.bytes(of: [resource(.photo, 3_200_000)]) == 3_200_000)
    }

    @Test func editedPhotoCountsOnlyTheCurrentVersion() {
        let resources = [
            resource(.photo, 3_200_000),
            resource(.fullSizePhoto, 3_500_000),
            resource(.adjustmentData, 1_500),
            resource(.adjustmentBasePhoto, 3_100_000),
        ]
        #expect(AssetSize.bytes(of: resources) == 3_500_000)
    }

    @Test func livePhotoIsThePhotoPlusItsVideoOnce() {
        let resources = [resource(.photo, 2_500_000), resource(.pairedVideo, 3_000_000)]
        #expect(AssetSize.bytes(of: resources) == 5_500_000)
    }

    @Test func editedLivePhotoUsesTheEditedPhotoAndVideo() {
        let resources = [
            resource(.photo, 2_500_000),
            resource(.pairedVideo, 3_000_000),
            resource(.fullSizePhoto, 2_700_000),
            resource(.fullSizePairedVideo, 2_900_000),
            resource(.adjustmentData, 1_000),
        ]
        #expect(AssetSize.bytes(of: resources) == 5_600_000)
    }

    @Test func otherAssetsUseTheirBiggestFile() {
        #expect(AssetSize.bytes(of: [resource(.alternatePhoto, 25_000_000)]) == 25_000_000)
        #expect(AssetSize.bytes(of: []) == 0)
    }

    @Test func formattingMatchesIOS() {
        #expect(ByteFormat.string(707_800_000) == "707.8 MB")
        #expect(ByteFormat.string(1_390_000_000) == "1.39 GB")
    }

    @Test func totalsCountEachAssetOnce() {
        let items: [(id: String, bytes: Int64)] = [("a", 100), ("b", 50), ("a", 100), ("c", 25), ("b", 50)]
        #expect(SizeMath.uniqueTotal(items) == 175)
        #expect(SizeMath.uniqueTotal([]) == 0)
    }
}

/// Real seeded videos: their size is exactly their one video file.
@Suite("Asset sizes on the seeded simulator",
       .enabled(if: PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized, "Needs Photos access"))
struct AssetSizeLibraryTests {
    @Test func seededVideoSizeIsItsVideoFile() throws {
        let video = try #require(PhotoLibrary.fetchVideos().first, "Needs seeded videos")
        let videoFile = PHAssetResource.assetResources(for: video).first { $0.type == .video }
        let bytes = try #require((videoFile?.value(forKey: "fileSize") as? NSNumber)?.int64Value)
        #expect(PhotoLibrary.fileSize(of: video) == bytes)
    }
}
