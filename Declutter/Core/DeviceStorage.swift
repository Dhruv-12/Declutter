import Foundation

/// Used and free space on the iPhone, as reported by iOS.
nonisolated struct DeviceStorage: Equatable, Sendable {
    let total: Int64
    let available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// The same as `current()`, off the main thread. iOS works out purgeable space for this, which can be slow.
    @concurrent
    static func load() async -> DeviceStorage? {
        current()
    }

    static func current() -> DeviceStorage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DeviceStorage(total: Int64(total), available: available)
    }
}

nonisolated enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
