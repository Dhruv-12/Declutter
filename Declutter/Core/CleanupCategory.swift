import SwiftUI

enum CleanupCategory: String, CaseIterable, Identifiable {
    case similarPhotos
    case screenshots
    case largeVideos
    case duplicateContacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .similarPhotos: "Similar photos"
        case .screenshots: "Screenshots"
        case .largeVideos: "Large videos"
        case .duplicateContacts: "Duplicate contacts"
        }
    }

    var systemImage: String {
        switch self {
        case .similarPhotos: "square.on.square"
        case .screenshots: "camera.viewfinder"
        case .largeVideos: "play.rectangle.fill"
        case .duplicateContacts: "person.2.fill"
        }
    }

    /// Every category uses the brand colour; categories are told apart by icon and name.
    var tint: Color { Theme.pine }

    var needsPhotos: Bool { self != .duplicateContacts }
}
