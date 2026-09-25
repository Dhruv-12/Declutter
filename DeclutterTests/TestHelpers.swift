import Contacts
import CoreGraphics
import Foundation
@testable import Declutter

/// Small builders shared by the unit tests.
enum Fixture {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// A photo fingerprint with a 2-number "print"; the distance between prints is plain Euclidean.
    static func photo(
        at seconds: TimeInterval,
        print: [Float]? = nil,
        hash: UInt64 = 0,
        shape: String = "3024x4032"
    ) -> PhotoFingerprint<[Float]> {
        PhotoFingerprint(date: start.addingTimeInterval(seconds), hash: hash, shape: shape, print: print)
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot()
    }

    static func group(
        _ photos: [PhotoFingerprint<[Float]>],
        threshold: Float = MatchStrictness.balanced.threshold,
        printFor: (Int) -> [Float]? = { _ in nil }
    ) -> [[Int]] {
        SimilarGrouping.group(photos, threshold: threshold, distance: distance, printFor: printFor)
    }

    static func contact(
        _ given: String = "",
        _ family: String = "",
        phones: [String] = [],
        emails: [String] = [],
        organization: String = "",
        image: Data? = nil
    ) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.organizationName = organization
        contact.phoneNumbers = phones.map { CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0)) }
        contact.emailAddresses = emails.map { CNLabeledValue(label: CNLabelHome, value: $0 as NSString) }
        contact.imageData = image
        return contact
    }

    static func summary(
        _ id: String,
        name: String,
        phones: [String] = [],
        emails: [String] = [],
        thumbnail: Data? = nil,
        fields: Int = 1
    ) -> ContactSummary {
        ContactSummary(id: id, name: name, organization: "", phones: phones, emails: emails, thumbnail: thumbnail, fieldCount: fields)
    }

    /// Draws a test image: `draw` gets a context of `width` × `height` pixels.
    static func image(width: Int = 256, height: Int = 256, _ draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context)
        return context.makeImage()!
    }

    static func checkerboard(cell: Int, size: Int = 256) -> CGImage {
        image(width: size, height: size) { context in
            for row in 0..<(size / cell) {
                for column in 0..<(size / cell) {
                    let white = (row + column) % 2 == 0
                    context.setFillColor(gray: white ? 1 : 0, alpha: 1)
                    context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
                }
            }
        }
    }

    /// The same checkerboard, drawn tiny and scaled up, so its edges are soft.
    static func blurredCheckerboard(cell: Int, size: Int = 256) -> CGImage {
        let small = checkerboard(cell: max(cell / 8, 1), size: size / 8)
        return image(width: size, height: size) { context in
            context.interpolationQuality = .high
            context.draw(small, in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
