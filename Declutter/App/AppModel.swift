import Contacts
import Observation
import Photos
import SwiftUI

/// App-wide state: permissions, device storage and the media the dashboard summarises.
@Observable
final class AppModel {
    private(set) var photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
    private(set) var storage = DeviceStorage.current()

    private(set) var screenshots: [MediaItem] = []
    private(set) var videos: [MediaItem] = []
    private(set) var isLoadingLibrary = false

    // What the user has picked in each screen. Kept here so it survives leaving the screen.
    var screenshotSelection: Set<String> = []
    var videoSelection: Set<String> = []

    let similar = SimilarPhotosModel()
    let contacts = ContactsModel()

    @ObservationIgnored private var libraryObserver: PhotoLibraryObserver?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() async {
        refreshPermissions()
        if contactsStatus.canRead { Task { await contacts.scan() } }
        await reloadLibrary()
    }

    func refreshStorage() {
        storage = DeviceStorage.current()
    }

    func refreshPermissions() {
        let newPhotoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let photoAccessChanged = newPhotoStatus != photoStatus
        photoStatus = newPhotoStatus
        if photoAccessChanged { scheduleReload() }

        let newContactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        if newContactsStatus != contactsStatus {
            contactsStatus = newContactsStatus
            contactsAccessChanged()
        }
    }

    // MARK: - Permissions

    func requestPhotoAccess() async {
        photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await reloadLibrary()
    }

    func requestContactsAccess() async {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        contactsAccessChanged()
    }

    private func contactsAccessChanged() {
        if contactsStatus.canRead {
            Task { await contacts.scan() }
        } else {
            contacts.reset()
        }
    }

    // MARK: - Photo library

    func reloadLibrary() async {
        guard photoStatus.canRead else {
            screenshots = []
            videos = []
            screenshotSelection = []
            videoSelection = []
            similar.cancelAndReset()
            return
        }
        if libraryObserver == nil {
            libraryObserver = PhotoLibraryObserver { [weak self] in self?.scheduleReload() }
        }
        isLoadingLibrary = true
        let media = await PhotoLibrary.loadDashboardMedia()
        screenshots = media.screenshots
        videos = media.videos
        // Forget selections for anything that no longer exists.
        screenshotSelection.formIntersection(screenshots.map(\.id))
        videoSelection.formIntersection(videos.map(\.id))
        isLoadingLibrary = false
        refreshStorage()

        // Start the similar-photo scan in the background so the dashboard can show what it finds.
        if similar.state == .idle { similar.scan() }
    }

    func removeMedia(_ ids: Set<String>) {
        screenshots.removeAll { ids.contains($0.id) }
        videos.removeAll { ids.contains($0.id) }
        screenshotSelection.subtract(ids)
        videoSelection.subtract(ids)
    }

    /// Photo library change notifications arrive in bursts, so wait a moment before reloading.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await reloadLibrary()
        }
    }

    // MARK: - Dashboard summaries

    func summary(for category: CleanupCategory) -> CategorySummary {
        switch category {
        case .screenshots:
            return mediaSummary(screenshots)
        case .largeVideos:
            return mediaSummary(videos)
        case .similarPhotos:
            guard photoStatus.canRead else { return .needsAccess }
            switch similar.state {
            case .idle: return .notScanned
            case .scanning(let progress): return .scanning(progress: progress)
            case .done: return .ready(count: similar.extras.count, bytes: similar.extras.totalSize)
            }
        case .duplicateContacts:
            guard contactsStatus.canRead else { return .needsAccess }
            switch contacts.state {
            case .idle, .failed: return .notScanned
            case .scanning where contacts.groups.isEmpty: return .loading
            default: return .ready(count: contacts.duplicateCount, bytes: nil)
            }
        }
    }

    /// Space that could be freed across every category we have numbers for.
    var reclaimableBytes: Int64 {
        CleanupCategory.allCases.reduce(0) { total, category in
            if case .ready(_, let bytes) = summary(for: category) { return total + (bytes ?? 0) }
            return total
        }
    }

    private func mediaSummary(_ items: [MediaItem]) -> CategorySummary {
        guard photoStatus.canRead else { return .needsAccess }
        if isLoadingLibrary && items.isEmpty { return .loading }
        return .ready(count: items.count, bytes: items.totalSize)
    }
}

enum CategorySummary: Equatable {
    case needsAccess
    case loading
    case scanning(progress: Double)
    case notScanned
    case ready(count: Int, bytes: Int64?)
}
