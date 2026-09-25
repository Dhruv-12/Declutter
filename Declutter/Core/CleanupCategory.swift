import SwiftUI

enum CleanupCategory: String, CaseIterable, Identifiable {
    case similarPhotos
    case screenshots
    case largeVideos
    case duplicateContacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .similarPhotos: "Similar Photos"
        case .screenshots: "Screenshots"
        case .largeVideos: "Large Videos"
        case .duplicateContacts: "Duplicate Contacts"
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

    var tint: Color {
        switch self {
        case .similarPhotos: .indigo
        case .screenshots: .orange
        case .largeVideos: .pink
        case .duplicateContacts: .green
        }
    }

    var needsPhotos: Bool { self != .duplicateContacts }
}
