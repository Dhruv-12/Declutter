import Photos
import SwiftUI

/// Everything the user has chosen to remove, frozen at the moment they open the review screen.
struct CleanupPlan: Identifiable {
    /// One group of photos or videos on the review screen, from a category or a tool.
    struct MediaSection: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let tint: Color
        let items: [MediaItem]
        /// Similar photos get an extra warning when every photo in a set is selected.
        var isSimilarPhotos = false

        init(category: CleanupCategory, items: [MediaItem]) {
            id = category.id
            title = category.title
            systemImage = category.systemImage
            tint = category.tint
            self.items = items
            isSimilarPhotos = category == .similarPhotos
        }

        init(tool: Tool, items: [MediaItem]) {
            id = tool.id
            title = tool.title
            systemImage = tool.systemImage
            tint = tool.tint
            self.items = items
        }
    }

    let id = UUID()
    let mediaSections: [MediaSection]
    let contacts: [ContactSummary]
    /// Similar-photo groups where every photo is selected, so none would be kept.
    let fullySelectedGroups: Int
    var events: [EventSummary] = []

    var isEmpty: Bool { mediaSections.allSatisfy(\.items.isEmpty) && contacts.isEmpty && events.isEmpty }
}

struct CleanupResult {
    var photosDeleted = 0
    var videosDeleted = 0
    var contactsDeleted = 0
    var eventsDeleted = 0
    var bytesFreed: Int64 = 0
    /// Set when photos were removed but contacts couldn't be.
    var contactsError: String?
    /// Set when other things were removed but calendar events couldn't be.
    var eventsError: String?

    var totalItems: Int { photosDeleted + videosDeleted + contactsDeleted + eventsDeleted }
}

enum CleanupError: LocalizedError {
    /// The user tapped "Don't Allow" on the iOS delete prompt. Nothing was deleted.
    case cancelled

    var errorDescription: String? { "Nothing was deleted." }
}

extension AppModel {
    /// Everything selected anywhere in the app, as the home screen's Review All bar counts it.
    /// A photo picked in two places (say, Similar photos and Swipe to sort) counts once.
    var selectedCount: Int { homeSelectedMedia.count + contacts.selection.count + calendar.selection.count }

    var selectedBytes: Int64 { homeSelectedMedia.totalSize }

    private var homeSelectedMedia: [MediaItem] {
        var seen = Set<String>()
        let all = CleanupCategory.allCases.flatMap(selectedMedia(in:)) + toolSelections.flatMap(\.items)
        return all.filter { seen.insert($0.id).inserted }
    }

    /// What each tool has picked for deletion.
    private var toolSelections: [(tool: Tool, items: [MediaItem])] {
        [(.swipe, swipe.marked), (.blurry, blurry.selectedItems)]
    }

    /// The home screen's Review All: every category plus what the tools picked, each photo listed once.
    func makeHomePlan() -> CleanupPlan {
        let plan = makePlan()
        var listed = Set(plan.mediaSections.flatMap { $0.items.map(\.id) })
        var sections = plan.mediaSections
        for (tool, items) in toolSelections {
            let fresh = items.filter { listed.insert($0.id).inserted }
            if !fresh.isEmpty { sections.append(.init(tool: tool, items: fresh)) }
        }
        return CleanupPlan(mediaSections: sections, contacts: plan.contacts, fullySelectedGroups: plan.fullySelectedGroups,
                           events: calendar.selectedEvents)
    }

    /// Calendar events the user selected.
    func makeCalendarPlan() -> CleanupPlan {
        CleanupPlan(mediaSections: [], contacts: [], fullySelectedGroups: 0, events: calendar.selectedEvents)
    }

    /// Photos marked in Swipe to sort.
    func makeSwipePlan() -> CleanupPlan { toolPlan(.swipe, swipe.marked) }

    /// Blurry photos the user selected.
    func makeBlurryPlan() -> CleanupPlan { toolPlan(.blurry, blurry.selectedItems) }

    /// The original of a video that now has a smaller copy.
    func makeCompressPlan(original: MediaItem) -> CleanupPlan { toolPlan(.compress, [original]) }

    private func toolPlan(_ tool: Tool, _ items: [MediaItem]) -> CleanupPlan {
        CleanupPlan(mediaSections: items.isEmpty ? [] : [.init(tool: tool, items: items)], contacts: [], fullySelectedGroups: 0)
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

    /// A review of every item in a category, for "Delete all". It doesn't touch the user's selection,
    /// so cancelling the review leaves everything as it was.
    func makeDeleteAllPlan(_ category: CleanupCategory) -> CleanupPlan {
        let items: [MediaItem] = switch category {
        case .screenshots: screenshots
        case .largeVideos: videos
        case .similarPhotos: similar.extras
        case .duplicateContacts: []
        }
        return CleanupPlan(
            mediaSections: items.isEmpty ? [] : [.init(category: category, items: items)],
            contacts: [],
            fullySelectedGroups: 0
        )
    }

    /// Deletes exactly the given items. Only ever called from the review screen after the user confirms.
    func performCleanup(
        media: [MediaItem],
        contacts contactsToDelete: [ContactSummary],
        events eventsToDelete: [EventSummary] = []
    ) async throws -> CleanupResult {
        var result = CleanupResult()

        // Photos first: iOS asks for confirmation, and if the user declines we stop before touching contacts.
        var seen = Set<String>()
        var uniqueMedia = media.filter { seen.insert($0.id).inserted }

        // Skip anything already deleted elsewhere, so the "space freed" total only counts real deletions.
        let existing = await PhotoLibrary.existingIDs(uniqueMedia.map(\.id))
        let alreadyGone = Set(uniqueMedia.map(\.id)).subtracting(existing)
        if !alreadyGone.isEmpty { removeDeletedMedia(alreadyGone) }
        uniqueMedia.removeAll { alreadyGone.contains($0.id) }

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
                if uniqueMedia.isEmpty && eventsToDelete.isEmpty { throw error }
            }
        }

        if !eventsToDelete.isEmpty {
            do {
                let ids = eventsToDelete.map(\.id)
                result.eventsDeleted = try await CalendarService.delete(ids)
                calendar.remove(Set(ids))
            } catch {
                result.eventsError = error.localizedDescription
                if result.totalItems == 0 && result.contactsError == nil { throw error }
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
        swipe.remove(ids)
        blurry.remove(ids)
        compress.remove(ids)
    }
}
