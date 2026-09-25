import Foundation
import Observation

/// One compressed video: the original, the smaller copy saved next to it, and their sizes.
struct CompressionRecord: Identifiable, Equatable {
    let originalID: String
    let copyID: String
    let originalBytes: Int64
    let copyBytes: Int64
    /// True once the original has been deleted, so the saving is real.
    var originalDeleted = false

    var id: String { copyID }
    var saving: Int64 { max(originalBytes - copyBytes, 0) }
}

/// Remembers what was compressed while the app is open, and how much space that saved.
@Observable
final class CompressVideosModel {
    private(set) var records: [CompressionRecord] = []

    /// Smaller copies made here, so the list can label them.
    var copyIDs: Set<String> { Set(records.map(\.copyID)) }

    /// Space saved by compressing, counting only originals that have been deleted.
    var totalSaved: Int64 {
        records.filter(\.originalDeleted).reduce(0) { $0 + $1.saving }
    }

    func add(_ record: CompressionRecord) {
        records.append(record)
    }

    /// Called after photos are deleted anywhere in the app.
    func remove(_ ids: Set<String>) {
        for index in records.indices where ids.contains(records[index].originalID) {
            records[index].originalDeleted = true
        }
        records.removeAll { ids.contains($0.copyID) }
    }

    func reset() {
        records = []
    }
}
