import Foundation
import Testing
@testable import Declutter

@Suite("Storage widget")
struct WidgetTests {
    @Test func summaryShowsFreeUsedAndTotal() {
        let summary = StorageSummary(DeviceStorage(total: 128_000_000_000, available: 41_200_000_000))
        #expect(summary.free == "41.2 GB")
        #expect(summary.used == "86.8 GB")
        #expect(summary.total == "128 GB")
        #expect(abs(summary.usedFraction - 0.678125) < 0.000001)
        #expect(summary.accessibilityLabel == "41.2 GB free of 128 GB. 86.8 GB used.")
    }

    @Test func barStaysInsideItsTrack() {
        #expect(StorageSummary(DeviceStorage(total: 100, available: 0)).usedFraction == 1)
        #expect(StorageSummary(DeviceStorage(total: 100, available: 100)).usedFraction == 0)
        // Nonsense from the system (more free than total) doesn't overflow the bar.
        #expect(StorageSummary(DeviceStorage(total: 100, available: 150)).usedFraction == 0)
        #expect(StorageSummary(DeviceStorage(total: 0, available: 0)).usedFraction == 0)
    }

    /// The widget ships inside the app, so it shows up in the Home Screen widget gallery.
    @Test func appShipsTheWidgetExtension() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let widget = try #require(Bundle(url: plugIns.appendingPathComponent("DeclutterWidgetExtension.appex")))
        #expect(widget.bundleIdentifier == "com.dhruv.Declutter.DeclutterWidget")
        let extensionInfo = widget.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
        #expect(extensionInfo?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
        #expect(widget.object(forInfoDictionaryKey: "MinimumOSVersion") as? String == "17.0")
    }
}
