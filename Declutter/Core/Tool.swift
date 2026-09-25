import SwiftUI

/// Extra tools shown as tiles on the home screen, below the clean-up categories.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case swipe
    case blurry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swipe: "Swipe to sort"
        case .blurry: "Blurry photos"
        }
    }

    var subtitle: String {
        switch self {
        case .swipe: "Keep or delete, one photo at a time"
        case .blurry: "Out-of-focus shots, blurriest first"
        }
    }

    var systemImage: String {
        switch self {
        case .swipe: "rectangle.stack"
        case .blurry: "camera.metering.unknown"
        }
    }

    var tint: Color {
        switch self {
        case .swipe: Theme.iris
        case .blurry: Theme.slate
        }
    }
}
