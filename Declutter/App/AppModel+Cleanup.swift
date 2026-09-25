import Photos
import SwiftUI

/// Everything the user has chosen to remove, frozen at the moment they open the review screen.
struct CleanupPlan: Identifiable {
    struct MediaSection: Identifiable {
        let category: CleanupCategory
        let items: [MediaItem]
        var id: String { category.id }
    }

    let id = UUID()
    let mediaSections: [MediaSection]
    let contacts: [ContactSummary]
    /// Similar-photo groups where every photo is selected, so none would be kept.
    let fullySelectedGroups: Int

    var isEmpty: Bool { mediaSections.allSatisfy(\.items.isEmpty) && contacts.isEmpty }
}

struct CleanupResult {
    var photosDeleted = 0
    var videosDeleted = 0
    var contactsDeleted = 0
    var bytesFreed: Int64 = 0
    /// Set when photos were removed but contacts couldn't be.
    var contactsError: String?

    var totalItems: Int { photosDeleted + videosDeleted + contactsDeleted }
}

enum CleanupError: LocalizedError {
    /// The user tapped "Don't Allow" on the iOS delete prompt. Nothing was deleted.
    case cancelled

    var errorDescription: String? { "Nothing was deleted." }
}

extension AppModel {
    var selectedCount: Int {
        screenshotSelection.count + videoSelection.count + similar.selection.count + contacts.selection.count
    }

    var selectedBytes: Int64 {
        CleanupCategory.allCases.reduce(0) { $0 + selectedMedia(in: $1).totalSize }
    }

    func selectedMedia(in category: CleanupCategory) -> [MediaItem] {
        switch category {
        case .screenshots: screenshots.filter { screenshotSelection.contains($0.id) }
        case .largeVideos: videos.filter { videoSelection.contains($0.id) }
        case .similarPhotos: similar.selectedItems
        case .duplicateContacts: []
        }
    }

    func makePlan(for categories: [CleanupCategory] = CleanupCategory.allCases) -> CleanupPlan {
        let sections = categories
            .filter { $0 != .duplicateContacts }
            .map { CleanupPlan.MediaSection(category: $0, items: selectedMedia(in: $0)) }
            .filter { !$0.items.isEmpty }
        let fullGroups = categories.contains(.similarPhotos)
            ? similar.groups.filter { $0.items.allSatisfy { similar.selection.contains($0.id) } }.count
            : 0
        return CleanupPlan(
            mediaSections: sections,
            contacts: categories.contains(.duplicateContacts) ? contacts.selectedContacts : [],
            fullySelectedGroups: fullGroups
        )
    }

    /// Deletes exactly the given items. Only ever called from the review screen after the user confirms.
    func performCleanup(media: [MediaItem], contacts contactsToDelete: [ContactSummary]) async throws -> CleanupResult {
        var result = CleanupResult()

        // Photos first: iOS asks for confirmation, and if the user declines we stop before touching contacts.
        var seen = Set<String>()
        let uniqueMedia = media.filter { seen.insert($0.id).inserted }
        if !uniqueMedia.isEmpty {
            let ids = uniqueMedia.map(\.id)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                    PHAssetChangeRequest.deleteAssets(assets)
                }
            } catch let error as PHPhotosError where error.code == .userCancelled {
                throw CleanupError.cancelled
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
                throw CleanupError.cancelled
            }
            result.videosDeleted = uniqueMedia.filter { $0.asset.mediaType == .video }.count
            result.photosDeleted = uniqueMedia.count - result.videosDeleted
            result.bytesFreed = uniqueMedia.totalSize
            removeDeletedMedia(Set(ids))
        }

        if !contactsToDelete.isEmpty {
            do {
                try await contacts.delete(contactsToDelete.map(\.id))
                result.contactsDeleted = contactsToDelete.count
            } catch {
                result.contactsError = error.localizedDescription
                if uniqueMedia.isEmpty { throw error }
            }
        }

        refreshStorage()
        LifetimeStats.record(result)
        return result
    }

    /// Updates every list right away instead of waiting for the photo library to notify us.
    private func removeDeletedMedia(_ ids: Set<String>) {
        removeMedia(ids)
        similar.remove(ids)
    }
}
