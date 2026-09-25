import CoreGraphics
import Testing
@testable import Declutter

@Suite("Blurry photo detection")
struct BlurDetectorTests {
    private let sharp = Fixture.checkerboard(cell: 16)

    @Test func sharpPhotoIsNotBlurry() {
        let score = BlurDetector.score(of: sharp)
        #expect(score >= BlurLevel.loosest.threshold, "score \(score)")
    }

    @Test func outOfFocusPhotoIsVeryBlurry() {
        let score = BlurDetector.score(of: Fixture.gaussianBlurred(sharp, radius: 6))
        #expect(score < BlurLevel.veryBlurry.threshold, "score \(score)")
    }

    @Test func slightlySoftPhotoIsOnlyListedWhenAskedFor() {
        let score = BlurDetector.score(of: Fixture.gaussianBlurred(sharp, radius: 1.5))
        #expect(score >= BlurLevel.blurry.threshold, "score \(score)")
        #expect(score < BlurLevel.soft.threshold, "score \(score)")
    }

    @Test func blurrierMeansLowerScore() {
        let scores = [0.0, 1.0, 2.5, 5.0].map { radius in
            BlurDetector.score(of: radius == 0 ? sharp : Fixture.gaussianBlurred(sharp, radius: radius))
        }
        #expect(scores == scores.sorted(by: >), "scores \(scores)")
    }

    @Test func mostlyEmptySharpPhotoIsNotBlurry() {
        // Plenty of sky or wall, one crisp subject: judged by its sharpest edges, so it passes.
        let score = BlurDetector.score(of: Fixture.smallSharpSubject())
        #expect(score >= BlurLevel.loosest.threshold, "score \(score)")
    }

    @Test func blankPhotoScoresZero() {
        let grey = Fixture.image { context in
            context.setFillColor(gray: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        #expect(BlurDetector.score(of: grey) == 0)
    }

    @Test func listsBlurriestFirstAndOnlyBelowTheThreshold() {
        let scores: [Double] = [50, 3, 30, 10, .infinity, 21.9]
        #expect(BlurDetector.blurry(scores: scores, threshold: 22) == [1, 3, 5])
        #expect(BlurDetector.blurry(scores: scores, threshold: 40) == [1, 3, 5, 2])
        #expect(BlurDetector.blurry(scores: [], threshold: 22).isEmpty)
    }

    @Test func levelsGetLooser() {
        #expect(BlurLevel.veryBlurry.threshold < BlurLevel.blurry.threshold)
        #expect(BlurLevel.blurry.threshold < BlurLevel.soft.threshold)
        #expect(BlurLevel.loosest == .soft)
    }
}
