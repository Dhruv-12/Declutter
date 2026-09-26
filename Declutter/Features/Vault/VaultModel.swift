import LocalAuthentication
import Observation
import Photos
import UIKit

/// The private vault: locked with Face ID (or Touch ID) and a PIN, and locked again whenever the
/// app goes to the background.
@Observable
final class VaultModel {
    enum State: Equatable {
        /// No PIN yet: the vault hasn't been set up.
        case needsSetup
        case locked
        case unlocked
    }

    private(set) var state: State = VaultPIN.isSet ? .locked : .needsSetup
    private(set) var items: [VaultItem] = []
    private(set) var attempts = PINAttempts()
    private(set) var errorMessage: String?
    /// Thumbnails decrypted for this session; cleared when the vault locks.
    @ObservationIgnored private var thumbnails: [UUID: UIImage] = [:]
    @ObservationIgnored private var store: VaultStore?

    /// "Face ID" or "Touch ID", or nil when neither is set up.
    var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    // MARK: Locking

    func setPIN(_ pin: String) {
        guard VaultPIN.isValid(pin), VaultPIN.save(pin) else {
            errorMessage = "The PIN couldn't be saved. Try again."
            return
        }
        open()
    }

    /// Returns false for a wrong PIN.
    @discardableResult
    func unlock(pin: String) -> Bool {
        guard !attempts.isLocked(at: .now) else { return false }
        guard VaultPIN.check(pin) else {
            attempts.recordMiss(at: .now)
            Haptics.warning()
            return false
        }
        attempts.recordSuccess()
        open()
        return true
    }

    /// Returns false if Face ID failed or was cancelled; the PIN still works.
    @discardableResult
    func unlockWithBiometrics() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        let success = (try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock your private vault"
        )) ?? false
        if success { open() }
        return success
    }

    func lock() {
        guard state == .unlocked else { return }
        items = []
        thumbnails = [:]
        store = nil
        state = .locked
    }

    private func open() {
        do {
            let store = try VaultStore.onDevice()
            self.store = store
            items = try store.items()
            errorMessage = nil
            state = .unlocked
            Haptics.success()
        } catch {
            errorMessage = "The vault couldn't be opened: \(error.localizedDescription)"
        }
    }

    // MARK: Photos

    func thumbnail(for item: VaultItem) async -> UIImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let store else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            (try? store.thumbnail(item.id)).flatMap(UIImage.init(data:))
        }.value
        if state == .unlocked { thumbnails[item.id] = image }
        return image
    }

    func fullPhoto(for item: VaultItem) async -> UIImage? {
        guard let store else { return nil }
        return await Task.detached(priority: .userInitiated) {
            (try? store.photo(item.id)).flatMap(UIImage.init(data:))
        }.value
    }

    /// Copies photos into the vault. The result lists the originals that are safely in the vault
    /// (only those may be offered for deletion) and why any others failed.
    func add(_ assets: [PHAsset], progress: @escaping @MainActor @Sendable (VaultImportProgress) -> Void) async -> VaultImportResult {
        guard let store else {
            let failures = assets.map {
                VaultImportFailure(id: $0.localIdentifier, takenAt: $0.creationDate,
                                   error: .save(detail: "the vault locked before the photos were added"))
            }
            return VaultImportResult(copied: [], failures: failures)
        }
        let result = await VaultTransfer.copyIn(assets, to: store, progress: progress)
        items = (try? store.items()) ?? items
        return result
    }

    func saveToPhotos(_ ids: Set<UUID>) async throws {
        guard let store else { return }
        try await VaultTransfer.saveToPhotos(items.filter { ids.contains($0.id) }, from: store)
    }

    /// Permanently removes photos from the vault.
    func delete(_ ids: Set<UUID>) throws {
        guard let store else { return }
        try store.delete(ids)
        for id in ids { thumbnails[id] = nil }
        items = try store.items()
    }
}
