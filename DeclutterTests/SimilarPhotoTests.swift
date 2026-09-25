import CoreGraphics
import Foundation
import Testing
@testable import Declutter

@Suite("Similar-photo grouping")
struct SimilarGroupingTests {
    @Test func nearDuplicatesTakenTogetherAreGrouped() {
        let photos = [
            Fixture.photo(at: 0, print: [0, 0]),
            Fixture.photo(at: 5, print: [0.1, 0]),
            Fixture.photo(at: 10, print: [0.2, 0]),
        ]
        #expect(Fixture.group(photos) == [[0, 1, 2]])
    }

    @Test func differentScenesTakenTogetherStaySeparate() {
        let photos = [
            Fixture.photo(at: 0, print: [0, 0]),
            Fixture.photo(at: 5, print: [5, 0]),
        ]
        #expect(Fixture.group(photos).isEmpty)
    }

    @Test func lookalikesTakenDaysApartAreNotSimilarShots() {
        let photos = [
            Fixture.photo(at: 0, print: [0, 0], hash: 0xA1),
            Fixture.photo(at: 86_400, print: [0, 0], hash: 0xB2),
        ]
        #expect(Fixture.group(photos).isEmpty)
    }

    @Test func exactDuplicatesMonthsApartAreGroupedByFingerprint() {
        let photos = [
            Fixture.photo(at: 0, hash: 0xABCDEF),
            Fixture.photo(at: 30 * 86_400, hash: 0xABCDEF),
        ]
        // Neither photo was in a burst, so their prints are computed on demand.
        let groups = Fixture.group(photos, printFor: { _ in [0, 0] })
        #expect(groups == [[0, 1]])
    }

    @Test func fingerprintCollisionIsRejectedByVisionCheck() {
        let photos = [
            Fixture.photo(at: 0, hash: 0xABCDEF),
            Fixture.photo(at: 30 * 86_400, hash: 0xABCDEF),
        ]
        let groups = Fixture.group(photos, printFor: { index in index == 0 ? [0, 0] : [3, 3] })
        #expect(groups.isEmpty)
    }

    @Test(arguments: [UInt64(0), UInt64.max])
    func trivialFingerprintsAreIgnored(hash: UInt64) {
        // All-black or all-white photos share a trivial fingerprint; they must not be lumped together.
        let photos = [
            Fixture.photo(at: 0, hash: hash),
            Fixture.photo(at: 86_400, hash: hash),
        ]
        #expect(Fixture.group(photos, printFor: { _ in [0, 0] }).isEmpty)
    }

    @Test func sameFingerprintDifferentShapeIsNotADuplicate() {
        let photos = [
            Fixture.photo(at: 0, hash: 0x1234, shape: "1080x1920"),
            Fixture.photo(at: 86_400, hash: 0x1234, shape: "3024x4032"),
        ]
        #expect(Fixture.group(photos, printFor: { _ in [0, 0] }).isEmpty)
    }

    @Test func rotatedCopyHasTheSameShape() {
        #expect(SimilarGrouping.shape(width: 4032, height: 3024) == SimilarGrouping.shape(width: 3024, height: 4032))
    }

    @Test func strictnessChangesWhatCountsAsSimilar() {
        let photos = [
            Fixture.photo(at: 0, print: [0, 0]),
            Fixture.photo(at: 10, print: [0.4, 0]),
        ]
        #expect(Fixture.group(photos, threshold: MatchStrictness.strict.threshold).isEmpty)
        #expect(Fixture.group(photos, threshold: MatchStrictness.balanced.threshold) == [[0, 1]])
        #expect(Fixture.group(photos, threshold: MatchStrictness.loose.threshold) == [[0, 1]])
        #expect(MatchStrictness.strict.threshold < MatchStrictness.balanced.threshold)
        #expect(MatchStrictness.balanced.threshold < MatchStrictness.loose.threshold)
    }

    @Test func similarShotsChainTogether() {
        // 0 is close to 1 and 1 is close to 2, even though 0 and 2 are further apart.
        let photos = [
            Fixture.photo(at: 0, print: [0, 0]),
            Fixture.photo(at: 3, print: [0.3, 0]),
            Fixture.photo(at: 6, print: [0.6, 0]),
        ]
        #expect(Fixture.group(photos) == [[0, 1, 2]])
    }

    @Test func onlyRecentNeighboursAreCompared() {
        // Seven unrelated photos sit between two lookalikes, so the last one never reaches the first.
        var photos = [Fixture.photo(at: 0, print: [0, 0])]
        for index in 1...7 { photos.append(Fixture.photo(at: Double(index), print: [Float(index) * 10, 0])) }
        photos.append(Fixture.photo(at: 8, print: [0, 0]))
        #expect(Fixture.group(photos).isEmpty)
    }

    @Test func emptyAndSinglePhotoLibraries() {
        #expect(Fixture.group([]).isEmpty)
        #expect(Fixture.group([Fixture.photo(at: 0, print: [0, 0])]).isEmpty)
    }

    @Test func photosWithoutDatesDontCrashOrGroup() {
        let photos = [
            PhotoFingerprint<[Float]>(date: nil, hash: 1, shape: "1x1", print: [0, 0]),
            PhotoFingerprint<[Float]>(date: nil, hash: 2, shape: "1x1", print: [0, 0]),
        ]
        #expect(Fixture.group(photos).isEmpty)
    }

    @Test func burstFlagsMarkPhotosTakenCloseTogether() {
        let t = Fixture.start
        let dates: [Date?] = [t, t + 10, t + 1_000, nil, t + 2_000, t + 2_050]
        #expect(SimilarGrouping.burstFlags(dates) == [true, true, false, false, true, true])
        #expect(SimilarGrouping.burstFlags([]) == [])
        #expect(SimilarGrouping.burstFlags([t]) == [false])
    }

    @Test func largeLibraryGroupsQuickly() {
        // 50,000 photos, one a minute, in sets of five near-identical shots taken 5 s apart.
        var photos: [PhotoFingerprint<[Float]>] = []
        photos.reserveCapacity(50_000)
        for index in 0..<50_000 {
            let set = index / 5
            photos.append(Fixture.photo(
                at: Double(set) * 600 + Double(index % 5) * 5,
                print: [Float(set) * 10, Float(index % 5) * 0.01],
                hash: UInt64(index + 1)
            ))
        }
        let clock = ContinuousClock()
        var groups: [[Int]] = []
        let elapsed = clock.measure { groups = Fixture.group(photos) }
        #expect(groups.count == 10_000)
        #expect(groups.allSatisfy { $0.count == 5 })
        #expect(elapsed < .seconds(10), "Grouping 50,000 photos took \(elapsed)")
    }
}

@Suite("Best photo in a set")
struct BestPhotoPickerTests {
    private func quality(sharpness: Double = 50, pixels: Double = 12_000_000, face: Double? = nil, favorite: Bool = false) -> PhotoQuality {
        PhotoQuality(isFavorite: favorite, pixels: pixels, sharpness: sharpness, faceQuality: face)
    }

    @Test func sharpestPhotoWins() {
        #expect(BestPhotoPicker.bestIndex([quality(sharpness: 10), quality(sharpness: 90), quality(sharpness: 40)]) == 1)
    }

    @Test func favouriteAlwaysWins() {
        #expect(BestPhotoPicker.bestIndex([quality(sharpness: 100), quality(sharpness: 5, favorite: true)]) == 1)
    }

    @Test func faceQualityCountsWhenTheSetHasFaces() {
        let set = [quality(sharpness: 100, face: 0.1), quality(sharpness: 90, face: 0.9)]
        #expect(BestPhotoPicker.bestIndex(set) == 1)
    }

    @Test func resolutionBreaksATie() {
        #expect(BestPhotoPicker.bestIndex([quality(pixels: 3_000_000), quality(pixels: 12_000_000)]) == 1)
    }

    @Test func edgeCases() {
        #expect(BestPhotoPicker.bestIndex([]) == 0)
        #expect(BestPhotoPicker.bestIndex([quality()]) == 0)
        #expect(BestPhotoPicker.bestIndex([quality(sharpness: 0), quality(sharpness: 0)]) == 0)
    }
}

@Suite("Image fingerprints")
struct ImageFingerprintTests {
    @Test func identicalImagesHaveIdenticalHashes() {
        let a = Fixture.checkerboard(cell: 32)
        let b = Fixture.checkerboard(cell: 32)
        #expect(SimilarPhotoScanner.differenceHash(of: a) == SimilarPhotoScanner.differenceHash(of: b))
    }

    @Test func differentImagesHaveDifferentHashes() {
        let gradient = Fixture.image { context in
            for x in 0..<256 {
                context.setFillColor(gray: CGFloat(x) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 256))
            }
        }
        let reversed = Fixture.image { context in
            for x in 0..<256 {
                context.setFillColor(gray: 1 - CGFloat(x) / 255, alpha: 1)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 256))
            }
        }
        #expect(SimilarPhotoScanner.differenceHash(of: gradient) != SimilarPhotoScanner.differenceHash(of: reversed))
    }

    @Test func flatImageHasATrivialHash() {
        let grey = Fixture.image { context in
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        #expect(SimilarPhotoScanner.differenceHash(of: grey) == 0)
    }

    @Test func sharpImageScoresHigherThanBlurredOne() {
        let sharp = SimilarPhotoScanner.sharpness(of: Fixture.checkerboard(cell: 16))
        let blurred = SimilarPhotoScanner.sharpness(of: Fixture.blurredCheckerboard(cell: 16))
        #expect(sharp > blurred * 2)
    }

    /// Checks that Vision works where the tests run (it is what decides "similar" in the app).
    // Skipped on the simulator: Vision can't create its model context there ("Failed to create
    // espresso context"), and the CPU fallback returns prints that don't tell images apart
    // (both distances came out identical). Similar photos work on real iPhones.
    @Test(.disabled(if: isSimulator, "Vision feature prints don't work on the iOS Simulator"))
    func visionTellsSimilarFromDifferentImages() throws {
        func scene(_ shift: Int, hue: CGFloat) -> CGImage {
            Fixture.image(width: 300, height: 300) { context in
                context.setFillColor(red: hue, green: 0.5, blue: 1 - hue, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
                context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
                context.fillEllipse(in: CGRect(x: 60 + shift, y: 80, width: 140, height: 140))
            }
        }
        let original = try #require(SimilarPhotoScanner.featurePrint(of: scene(0, hue: 0.2)))
        let nudged = try #require(SimilarPhotoScanner.featurePrint(of: scene(6, hue: 0.2)))
        let stripes = try #require(SimilarPhotoScanner.featurePrint(of: Fixture.checkerboard(cell: 20, size: 300)))
        let similar = SimilarPhotoScanner.distance(original, nudged)
        let different = SimilarPhotoScanner.distance(original, stripes)
        #expect(similar < different)
        #expect(similar <= MatchStrictness.balanced.threshold)
    }
}
