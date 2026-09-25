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

/// How the home storage bar splits used space. Pure logic, unit tested.
nonisolated struct StorageBreakdown: Equatable {
    /// Space freed this session (still counted as used by iOS until Recently Deleted empties).
    let freed: Int64
    /// Space the app could free, never more than what is used.
    let cleanable: Int64
    /// Everything else that is used.
    let otherUsed: Int64

    init(storage: DeviceStorage, cleanable: Int64, freed: Int64) {
        self.freed = min(max(freed, 0), storage.used)
        self.cleanable = min(max(cleanable, 0), storage.used - self.freed)
        self.otherUsed = storage.used - self.cleanable - self.freed
    }
}

nonisolated enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// "1 photo", "3 photos". Every count shown to people goes through this.
nonisolated func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
}
