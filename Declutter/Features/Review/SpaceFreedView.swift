import SwiftUI

/// Shown after a cleanup: how much space was freed, what was removed, and lifetime totals.
/// It stays still on purpose: the big moment plays on the home screen after "Back to home".
struct SpaceFreedView: View {
    let result: CleanupResult
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(LifetimeStats.bytesKey) private var lifetimeBytes = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing * 1.5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.onMint)
                    .frame(width: 72, height: 72)
                    .background(Theme.mint, in: .circle)
                    .accessibilityHidden(true)
                    .padding(.top, 40)

                VStack(alignment: .leading, spacing: 4) {
                    if result.bytesFreed > 0 {
                        Text(ByteFormat.string(result.bytesFreed))
                            .font(.heroNumber)
                            .foregroundStyle(Theme.mintText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("space freed")
                            .font(.heading(.title3))
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("All done")
                            .font(.heading(.largeTitle))
                            .foregroundStyle(Theme.pine)
                    }
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    if result.photosDeleted > 0 {
                        SummaryRow(icon: "photo", title: "Photos removed", value: "\(result.photosDeleted)")
                    }
                    if result.videosDeleted > 0 {
                        SummaryRow(icon: "video", title: "Videos removed", value: "\(result.videosDeleted)")
                    }
                    if result.contactsDeleted > 0 {
                        SummaryRow(icon: "person.crop.circle", title: "Contacts removed", value: "\(result.contactsDeleted)")
                    }
                    if let storage = model.storage {
                        SummaryRow(icon: "internaldrive", title: "Free on iPhone now", value: ByteFormat.string(storage.available))
                    }
                    SummaryRow(icon: "sparkles", title: "Freed with Declutter so far", value: ByteFormat.string(Int64(lifetimeBytes)), isLast: true)
                }
                .background(Theme.stone, in: .rect(cornerRadius: Theme.radius))

                if let error = result.contactsError {
                    Label("Contacts weren't deleted: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.coralText)
                }

                if result.photosDeleted + result.videosDeleted > 0 {
                    Label("Removed photos and videos wait in Recently Deleted in the Photos app for 30 days. To get the space back now, open Photos, go to Recently Deleted and choose Delete All.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.page)
        }
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            Button("Back to home", action: onDone)
                .buttonStyle(.primary)
                .padding(.horizontal, Theme.page)
                .padding(.vertical, 12)
                .background(Theme.mist.ignoresSafeArea())
        }
        .onAppear { Haptics.success() }
    }
}

private struct SummaryRow: View {
    let icon: String
    let title: String
    let value: String
    var isLast = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.pine)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(Theme.pine)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.pine)
        }
        .padding(Theme.spacing)
        .overlay(alignment: .bottom) {
            if !isLast { Theme.hairline.frame(height: 1).padding(.leading, 56) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Running totals across every cleanup, stored on the device.
enum LifetimeStats {
    static let bytesKey = "lifetimeBytesFreed"
    static let itemsKey = "lifetimeItemsRemoved"

    static func record(_ result: CleanupResult) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: bytesKey) + Int(result.bytesFreed), forKey: bytesKey)
        defaults.set(defaults.integer(forKey: itemsKey) + result.totalItems, forKey: itemsKey)
    }
}
