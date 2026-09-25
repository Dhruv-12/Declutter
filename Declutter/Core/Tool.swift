import SwiftUI

/// Extra tools shown as tiles on the home screen, below the clean-up categories.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case swipe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swipe: "Swipe to sort"
        }
    }

    var subtitle: String {
        switch self {
        case .swipe: "Keep or delete, one photo at a time"
        }
    }

    var systemImage: String {
        switch self {
        case .swipe: "rectangle.stack"
        }
    }

    var tint: Color {
        switch self {
        case .swipe: Theme.iris
        }
    }
}
