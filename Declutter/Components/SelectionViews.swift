import Photos
import SwiftUI

/// A thumbnail with a checkmark overlay when selected, and an optional "Best" badge.
struct SelectableThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    var isBest = false
    /// Small text in the bottom-left corner, such as a video's length.
    var badge: String? = nil

    var body: some View {
        AssetThumbnail(asset: asset)
            .overlay {
                if isSelected { Color.black.opacity(0.22) }
            }
            .overlay(alignment: .topLeading) {
                if isBest { BestBadge().padding(6) }
            }
            .overlay(alignment: .bottomLeading) {
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.5), in: .capsule)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                SelectionCheckmark(isSelected: isSelected)
                    .padding(6)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.thumbRadius)
                        .strokeBorder(Theme.pine, lineWidth: 2.5)
                }
            }
            .clipShape(.rect(cornerRadius: Theme.thumbRadius))
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isBest ? "Best photo" : (asset.mediaType == .video ? "Video" : "Photo"))
            .accessibilityIdentifier(isBest ? "thumbnail.best" : "thumbnail")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SelectionCheckmark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Theme.pineFill : Color.black.opacity(0.2))
            Circle()
                .strokeBorder(.white, lineWidth: 2)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.onPine)
            }
        }
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .tapAnimation(value: isSelected)
    }
}

struct BestBadge: View {
    var body: some View {
        Label("Best", systemImage: "star.fill")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.onPine)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.pineFill, in: .capsule)
    }
}

/// The sticky bar at the bottom of every screen: "Review 24 items · 1.2 GB".
struct SelectionBar: View {
    let count: Int
    var bytes: Int64? = nil
    var singular = "item"
    var plural = "items"
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Text(title)
                .contentTransition(.numericText())
        }
        .buttonStyle(.primary)
        .disabled(count == 0)
        .accessibilityIdentifier("reviewBar")
        .tapAnimation(value: count)
        .padding(.horizontal, Theme.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) {
            Theme.mist
                .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
                .ignoresSafeArea()
        }
    }

    private var title: String {
        guard count > 0 else { return "Select \(plural) to review" }
        let noun = count == 1 ? singular : plural
        let size = bytes.map { " · \(ByteFormat.string($0))" } ?? ""
        return "Review \(count) \(noun)\(size)"
    }
}

/// Every empty or blocked screen: an icon, a plain message, and what to do next.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.pine)
                .frame(width: 84, height: 84)
                .background(Theme.stone, in: .circle)
            VStack(spacing: Theme.gap) {
                Text(title)
                    .font(.heading(.title3))
                    .foregroundStyle(Theme.pine)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.compact(.primary))
                    .padding(.top, Theme.gap)
            }
        }
        .padding(Theme.page * 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// Shown in place of a screen's content when Photos access is off.
struct PhotoAccessNeededView: View {
    var body: some View {
        EmptyStateView(
            systemImage: "photo.badge.exclamationmark",
            title: "Photo access is off",
            message: "Turn on Photos access in Settings so Declutter can look through your library on this iPhone.",
            actionTitle: "Open Settings"
        ) {
            SystemSettings.open()
        }
    }
}

/// Text button that toggles between selecting everything and nothing, used in section headers.
struct SelectAllButton: View {
    let allIDs: [String]
    @Binding var selection: Set<String>

    private var allSelected: Bool {
        !allIDs.isEmpty && allIDs.allSatisfy(selection.contains)
    }

    var body: some View {
        Button(allSelected ? "Deselect all" : "Select all") {
            Haptics.select()
            if allSelected {
                selection.subtract(allIDs)
            } else {
                selection.formUnion(allIDs)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.pine)
        .disabled(allIDs.isEmpty)
    }
}

/// A bulk action whose label says how much it covers, e.g. "Delete all 243 (1.2 GB)".
struct BulkActionButton: View {
    let title: String
    let count: Int
    var bytes: Int64? = nil
    /// Shown in brackets instead of a size, for things without one (like contacts).
    var detail: String? = nil
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    private var label: String {
        let bracket = detail ?? bytes.map(ByteFormat.string)
        return "\(title) \(count)" + (bracket.map { " (\($0))" } ?? "")
    }

    var body: some View {
        Button(role: role) {
            Haptics.select()
            action()
        } label: {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(BrandButtonStyle(kind: role == .destructive ? .secondaryDestructive : .secondary))
        .disabled(count == 0)
    }
}

/// Lays bulk buttons side by side, or stacked when they don't fit.
struct BulkActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.gap) { content() }
            VStack(spacing: Theme.gap) { content() }
        }
        .padding(.horizontal, Theme.page)
    }
}

/// Small line of text under a screen's title: "243 screenshots · 1.2 GB".
struct ScreenSummary: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.pine)
                .accessibilityIdentifier("screenSummary")
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.page)
    }
}

/// Full-screen loading state.
struct LoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: Theme.spacing) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.pine)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
