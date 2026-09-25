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

    /// Soft colour for the category's icon.
    var tint: Color {
        switch self {
        case .similarPhotos: Theme.lake
        case .screenshots: Theme.amber
        case .largeVideos: Theme.plum
        case .duplicateContacts: Theme.teal
        }
    }

    var needsPhotos: Bool { self != .duplicateContacts }
}
