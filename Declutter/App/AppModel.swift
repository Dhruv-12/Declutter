import Contacts
import Observation
import Photos
import SwiftUI

/// App-wide state: permissions, device storage and the media the dashboard summarises.
@Observable
final class AppModel {
    // Nothing here touches the system while the model is created: permission checks and the
    // storage calculation can be slow, so `start()` reads them in the background after the
    // intro is on screen.
    private(set) var photoStatus: PHAuthorizationStatus = .notDetermined
    private(set) var contactsStatus: CNAuthorizationStatus = .notDetermined
    private(set) var storage: DeviceStorage?
    /// False until `start()` has read the real permission states.
    private(set) var hasStarted = false

    private(set) var screenshots: [MediaItem] = []
    private(set) var videos: [MediaItem] = []
    private(set) var isLoadingLibrary = false

    // What the user has picked in each screen. Kept here so it survives leaving the screen.
    var screenshotSelection: Set<String> = []
    var videoSelection: Set<String> = []

    /// The home screen's navigation stack, so a finished cleanup can return home.
    var path: [CleanupCategory] = []
    /// Space freed by cleanups since the app opened. Photos wait in Recently Deleted for 30 days,
    /// and iOS keeps counting them as used until then, so the home bar shows this separately.
    private(set) var freedThisSession: Int64 = 0
    /// Set after a cleanup to play the home screen's "space freed" animation once.
    var freedEvent: FreedEvent?

    let similar = SimilarPhotosModel()
    let contacts = ContactsModel()

    @ObservationIgnored private var libraryObserver: PhotoLibraryObserver?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// Runs once at launch, behind the intro. Every slow call happens off the main thread.
    func start() async {
        guard !hasStarted else { return }
        let statuses = await PermissionReader.current()
        photoStatus = statuses.photos
        contactsStatus = statuses.contacts
        hasStarted = true
        LaunchTimer.mark("Permissions read")

        refreshStorage()
        if contactsStatus.canRead { Task { await contacts.scan() } }
        await reloadLibrary()
    }

    /// Asks iOS for used and free space in the background; it can take a while.
    func refreshStorage() {
        Task {
            let isFirstLoad = storage == nil
            storage = await DeviceStorage.load()
            if isFirstLoad { LaunchTimer.mark("Storage loaded") }
        }
    }

    /// Re-reads permissions in the background, for example after a visit to the Settings app.
    func refreshPermissions() {
        guard hasStarted else { return }
        Task {
            let statuses = await PermissionReader.current()
            if statuses.photos != photoStatus {
                photoStatus = statuses.photos
                await photoAccessChanged()
            }
            if statuses.contacts != contactsStatus {
                contactsStatus = statuses.contacts
                contactsAccessChanged()
            }
        }
    }

    // MARK: - Permissions

    func requestPhotoAccess() async {
        photoStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await photoAccessChanged()
    }

    /// Access went from none to limited to full, or the user shared more photos:
    /// old similar-photo results no longer describe what we can see, so scan again.
    func photoAccessChanged() async {
        similar.cancelAndReset()
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
            // The first call to the shared photo library is slow, so register off the main thread.
            libraryObserver = await PhotoLibraryObserver.make { [weak self] in self?.scheduleReload() }
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
        similar.removeMissingPhotos()

        // Start the similar-photo scan in the background so the dashboard can show what it finds.
        if similar.state == .idle { similar.scan() }
    }

    /// After the summary: go back to the home screen and play the storage bar animation there.
    func returnHome(after result: CleanupResult) {
        path = []
        guard result.bytesFreed > 0 else { return }
        freedThisSession += result.bytesFreed
        freedEvent = FreedEvent(bytes: result.bytesFreed, reclaimableBefore: reclaimableBytes + result.bytesFreed)
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

struct FreedEvent: Equatable {
    let id = UUID()
    let bytes: Int64
    /// The "you can free" number before the cleanup, so the home screen can count down from it.
    let reclaimableBefore: Int64
}

enum CategorySummary: Equatable {
    case needsAccess
    case loading
    case scanning(progress: Double)
    case notScanned
    case ready(count: Int, bytes: Int64?)
}
