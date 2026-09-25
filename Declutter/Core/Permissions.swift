import Contacts
import Photos
import PhotosUI
import UIKit

extension PHAuthorizationStatus {
    /// Full or limited access both let us read (the limited set of) photos.
    var canRead: Bool { self == .authorized || self == .limited }
}

extension CNAuthorizationStatus {
    var canRead: Bool {
        if self == .authorized { return true }
        if #available(iOS 18.0, *), self == .limited { return true }
        return false
    }

    var isLimited: Bool {
        if #available(iOS 18.0, *) { return self == .limited }
        return false
    }
}

enum SystemSettings {
    /// Opens this app's page in the Settings app, where the user can change Photos and Contacts access.
    static func open() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Lets a user with limited Photos access pick more photos to share with the app.
    static func presentLimitedPhotoPicker() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
