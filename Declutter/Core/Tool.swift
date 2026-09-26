import SwiftUI

/// Extra tools shown as tiles on the home screen, below the clean-up categories.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case swipe
    case blurry
    case compress
    case widget
    case vault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swipe: "Swipe to sort"
        case .blurry: "Blurry photos"
        case .compress: "Compress videos"
        case .widget: "Home Screen widget"
        case .vault: "Private vault"
        }
    }

    var subtitle: String {
        switch self {
        case .swipe: "Keep or delete, one photo at a time"
        case .blurry: "Out-of-focus shots, blurriest first"
        case .compress: "Smaller copies of big videos"
        case .widget: "Free space at a glance"
        case .vault: "Photos locked with Face ID"
        }
    }

    var systemImage: String {
        switch self {
        case .swipe: "rectangle.stack"
        case .blurry: "camera.metering.unknown"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .widget: "square.grid.2x2"
        case .vault: "lock.shield"
        }
    }

    var tint: Color {
        switch self {
        case .swipe: Theme.iris
        case .blurry: Theme.slate
        case .compress: Theme.plum
        case .widget: Theme.teal
        case .vault: Theme.iris
        }
    }
}
