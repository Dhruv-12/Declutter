import SwiftUI
import WidgetKit

/// Home Screen widget: used and free space on this iPhone. It works out storage itself, using
/// the same code as the app, and refreshes every 30 minutes (and whenever the app cleans up).
/// Tapping it opens Declutter.
@main
struct DeclutterWidget: Widget {
    static let kind = "DeclutterStorage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StorageProvider()) { entry in
            StorageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Storage")
        .description("Used and free space on this iPhone.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StorageEntry: TimelineEntry {
    let date: Date
    let storage: DeviceStorage?
}

struct StorageProvider: TimelineProvider {
    /// Shown in the widget gallery before real data is ready.
    private static let example = DeviceStorage(total: 128_000_000_000, available: 41_200_000_000)

    func placeholder(in context: Context) -> StorageEntry {
        StorageEntry(date: .now, storage: Self.example)
    }

    func getSnapshot(in context: Context, completion: @escaping (StorageEntry) -> Void) {
        completion(StorageEntry(date: .now, storage: context.isPreview ? Self.example : DeviceStorage.current()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StorageEntry>) -> Void) {
        let entry = StorageEntry(date: .now, storage: DeviceStorage.current())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct StorageWidgetEntryView: View {
    let entry: StorageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        StorageWidgetView(storage: entry.storage, family: family)
    }
}
