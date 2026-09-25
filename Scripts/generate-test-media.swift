// Generates test photos, screenshots, videos and contacts for the simulator.
//
//   swiftc -O generate-test-media.swift -o generate-test-media
//   ./generate-test-media <output folder> <standard | unique | large> [photo count for large]
//
// standard: 3 near-identical shots taken seconds apart, 2 identical photos taken months apart,
//           4 unique photos, 5 screenshots, 3 large videos, contacts with 3 duplicate groups.
// unique:   8 unique photos and contacts with no duplicates.
// large:    many unique photos (default 1500), with a near-identical partner for every 50th.

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: generate-test-media <output folder> <standard|unique|large> [count]")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
let profile = arguments[2]
let largeCount = arguments.count > 3 ? Int(arguments[3]) ?? 1500 : 1500
try? FileManager.default.removeItem(at: output)
for folder in ["photos", "screenshots", "videos"] {
    try FileManager.default.createDirectory(at: output.appendingPathComponent(folder), withIntermediateDirectories: true)
}

// MARK: - Drawing

struct Scene {
    var background: (CGFloat, CGFloat, CGFloat)
    var shapes: [(rect: CGRect, color: (CGFloat, CGFloat, CGFloat), round: Bool)]
}

/// A repeatable pseudo-random scene, so every run produces the same library.
func scene(seed: Int) -> Scene {
    var state = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12345)
    func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
    let background = (next(), next(), next())
    let shapes = (0..<6).map { _ in
        (rect: CGRect(x: next() * 800, y: next() * 1100, width: 120 + next() * 380, height: 120 + next() * 380),
         color: (next(), next(), next()),
         round: next() > 0.5)
    }
    return Scene(background: background, shapes: shapes)
}

func render(_ scene: Scene, width: Int = 1200, height: Int = 1600, shift: CGFloat = 0, brightness: CGFloat = 0) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    let sx = CGFloat(width) / 1200, sy = CGFloat(height) / 1600
    func clamp(_ v: CGFloat) -> CGFloat { min(max(v + brightness, 0), 1) }
    context.setFillColor(red: clamp(scene.background.0), green: clamp(scene.background.1), blue: clamp(scene.background.2), alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for shape in scene.shapes {
        context.setFillColor(red: clamp(shape.color.0), green: clamp(shape.color.1), blue: clamp(shape.color.2), alpha: 1)
        let rect = CGRect(x: (shape.rect.minX + shift) * sx, y: shape.rect.minY * sy, width: shape.rect.width * sx, height: shape.rect.height * sy)
        if shape.round { context.fillEllipse(in: rect) } else { context.fill(rect) }
    }
    return context.makeImage()!
}

let exifFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter
}()

/// Writes an image with the date it was "taken". Screenshots get the EXIF comment iOS uses to mark them.
func write(_ image: CGImage, to url: URL, taken: Date, screenshot: Bool = false) {
    let type = screenshot ? UTType.png : UTType.jpeg
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var exif: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: exifFormatter.string(from: taken),
        kCGImagePropertyExifDateTimeDigitized: exifFormatter.string(from: taken),
    ]
    if screenshot { exif[kCGImagePropertyExifUserComment] = "Screenshot" }
    var properties: [CFString: Any] = [kCGImagePropertyExifDictionary: exif]
    if !screenshot { properties[kCGImageDestinationLossyCompressionQuality] = 0.9 }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
}

func date(_ text: String) -> Date { exifFormatter.date(from: text)! }

// MARK: - Videos

/// A noisy video (noise doesn't compress, so the file is big) with a creation date.
func writeVideo(to url: URL, seconds: Int, bitrate: Int, created: Date) throws {
    let width = 1280, height = 720, fps = 30
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let metadata = AVMutableMetadataItem()
    metadata.key = AVMetadataKey.commonKeyCreationDate as NSString
    metadata.keySpace = .common
    metadata.value = ISO8601DateFormatter().string(from: created) as NSString
    writer.metadata = [metadata]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var generator = SystemRandomNumberGenerator()
    for frame in 0..<(seconds * fps) {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt64.self)
        let words = CVPixelBufferGetBytesPerRow(pixels) * height / 8
        for index in 0..<words { base[index] = generator.next() }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}

// MARK: - Contacts

func vcard(_ given: String, _ family: String, phones: [String] = [], emails: [String] = []) -> String {
    var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:\(family);\(given);;;", "FN:\(given) \(family)"]
    lines += phones.map { "TEL;TYPE=CELL:\($0)" }
    lines += emails.map { "EMAIL;TYPE=HOME:\($0)" }
    lines.append("END:VCARD")
    return lines.joined(separator: "\r\n")
}

func writeContacts(_ cards: [String]) throws {
    try cards.joined(separator: "\r\n").write(to: output.appendingPathComponent("contacts.vcf"), atomically: true, encoding: .utf8)
}

// MARK: - Profiles

let photos = output.appendingPathComponent("photos")

switch profile {
case "standard":
    // Near-identical burst: same scene nudged slightly, 5 seconds apart.
    let burst = scene(seed: 1)
    for (index, shift) in [0, 6, 12].enumerated() {
        write(render(burst, shift: CGFloat(shift), brightness: CGFloat(index) * 0.01),
              to: photos.appendingPathComponent("burst-\(index).jpg"),
              taken: date("2026:01:10 10:00:0\(index * 5)"))
    }
    // Exact duplicates taken months apart (saved twice).
    let saved = render(scene(seed: 2))
    write(saved, to: photos.appendingPathComponent("saved-copy-1.jpg"), taken: date("2025:03:01 12:00:00"))
    write(saved, to: photos.appendingPathComponent("saved-copy-2.jpg"), taken: date("2025:09:01 12:00:00"))
    // Unique photos days apart.
    for index in 0..<4 {
        write(render(scene(seed: 100 + index)), to: photos.appendingPathComponent("unique-\(index).jpg"),
              taken: date("2025:0\(index + 4):15 08:00:00"))
    }
    // Screenshots.
    for index in 0..<5 {
        write(render(scene(seed: 200 + index), width: 1179, height: 2556),
              to: output.appendingPathComponent("screenshots/screenshot-\(index).png"),
              taken: date("2026:02:0\(index + 1) 18:30:00"), screenshot: true)
    }
    // Large videos of different sizes.
    for (index, (seconds, bitrate)) in [(3, 8_000_000), (8, 12_000_000), (16, 16_000_000)].enumerated() {
        try writeVideo(to: output.appendingPathComponent("videos/video-\(index).mov"),
                       seconds: seconds, bitrate: bitrate, created: date("2026:03:0\(index + 1) 09:00:00"))
    }
    try writeContacts([
        vcard("Asha", "Verma", phones: ["+91 98765 43210"], emails: ["asha@example.com"]),
        vcard("Asha", "Verma", phones: ["9876543210"]),
        vcard("Rahul", "Mehta", emails: ["rahul@example.com"]),
        vcard("Rahul", "M", emails: ["RAHUL@example.com"]),
        vcard("Neha", "Kapoor", phones: ["+1 415 555 0101"]),
        vcard("Kapoor", "Neha"),
        vcard("Vikram", "Singh", phones: ["+91 90000 11111"]),
        vcard("Priya", "Nair", emails: ["priya@example.com"]),
    ])

case "unique":
    for index in 0..<8 {
        write(render(scene(seed: 300 + index)), to: photos.appendingPathComponent("unique-\(index).jpg"),
              taken: date("2025:0\(index + 1):20 08:00:00"))
    }
    try writeContacts([
        vcard("Vikram", "Singh", phones: ["+91 90000 11111"]),
        vcard("Priya", "Nair", emails: ["priya@example.com"]),
        vcard("Arjun", "Rao", phones: ["+91 90000 33333"], emails: ["arjun@example.com"]),
    ])

case "large":
    // One photo an hour, each different; every 50th gets a near-identical partner 3 seconds later.
    let base = date("2024:01:01 00:00:00")
    for index in 0..<largeCount {
        let taken = base.addingTimeInterval(Double(index) * 3600)
        let picture = scene(seed: 10_000 + index)
        write(render(picture, width: 600, height: 800), to: photos.appendingPathComponent("large-\(index).jpg"), taken: taken)
        if index % 50 == 0 {
            write(render(picture, width: 600, height: 800, shift: 6), to: photos.appendingPathComponent("large-\(index)-b.jpg"),
                  taken: taken.addingTimeInterval(3))
        }
    }
    try writeContacts([])

default:
    print("unknown profile \(profile)")
    exit(1)
}

let count = { (folder: String) in
    (try? FileManager.default.contentsOfDirectory(atPath: output.appendingPathComponent(folder).path).count) ?? 0
}
print("Generated \(profile): \(count("photos")) photos, \(count("screenshots")) screenshots, \(count("videos")) videos")
