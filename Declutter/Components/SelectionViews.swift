import Photos
import SwiftUI

/// A thumbnail with a checkmark that shows whether it is selected.
struct SelectableThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    var badge: String? = nil

    var body: some View {
        AssetThumbnail(asset: asset)
            .overlay {
                if isSelected { Color.black.opacity(0.25) }
            }
            .overlay(alignment: .bottomLeading) {
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                SelectionCheckmark(isSelected: isSelected)
                    .padding(6)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SelectionCheckmark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : .black.opacity(0.3))
            Circle()
                .strokeBorder(.white, lineWidth: 1.5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .shadow(color: .black.opacity(0.2), radius: 2)
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

/// Bar pinned to the bottom of a screen that sums up the current selection.
struct SelectionBar: View {
    let count: Int
    let bytes: Int64
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) selected")
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(ByteFormat.string(bytes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(count == 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.default, value: count)
    }
}

/// Shown in place of a screen's content when Photos access is off.
struct PhotoAccessNeededView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Photo Access Needed", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Turn on Photos access in Settings so Declutter can scan your library on this iPhone.")
        } actions: {
            Button("Open Settings") { SystemSettings.open() }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// Toolbar button that toggles between selecting everything and nothing.
struct SelectAllButton: View {
    let allIDs: [String]
    @Binding var selection: Set<String>

    private var allSelected: Bool {
        !allIDs.isEmpty && allIDs.allSatisfy(selection.contains)
    }

    var body: some View {
        Button(allSelected ? "Deselect All" : "Select All") {
            if allSelected {
                selection.subtract(allIDs)
            } else {
                selection.formUnion(allIDs)
            }
        }
        .disabled(allIDs.isEmpty)
    }
}
