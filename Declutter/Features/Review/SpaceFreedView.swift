import SwiftUI

/// Shown after a cleanup: how much space was freed, what was removed, and lifetime totals.
struct SpaceFreedView: View {
    let result: CleanupResult
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(LifetimeStats.bytesKey) private var lifetimeBytes = 0
    @AppStorage(LifetimeStats.itemsKey) private var lifetimeItems = 0

    @State private var shownBytes: Int64 = 0
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.gradient)
                        .frame(width: 110, height: 110)
                        .shadow(color: .accentColor.opacity(0.4), radius: 16, y: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: appeared)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .padding(.top, 32)

                VStack(spacing: 6) {
                    Text(result.bytesFreed > 0 ? "Space Freed" : "All Done")
                        .font(.title2.bold())
                    if result.bytesFreed > 0 {
                        Text(ByteFormat.string(shownBytes))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.tint)
                            .contentTransition(.numericText(value: Double(shownBytes)))
                    }
                }

                VStack(spacing: 0) {
                    if result.photosDeleted > 0 {
                        SummaryRow(icon: "photo", tint: .indigo, title: "Photos removed", value: "\(result.photosDeleted)")
                    }
                    if result.videosDeleted > 0 {
                        SummaryRow(icon: "video", tint: .pink, title: "Videos removed", value: "\(result.videosDeleted)")
                    }
                    if result.contactsDeleted > 0 {
                        SummaryRow(icon: "person.crop.circle", tint: .green, title: "Contacts removed", value: "\(result.contactsDeleted)")
                    }
                    if let storage = model.storage {
                        SummaryRow(icon: "internaldrive", tint: .gray, title: "Free on iPhone now", value: ByteFormat.string(storage.available))
                    }
                    SummaryRow(icon: "trophy", tint: .orange, title: "Freed with Declutter so far", value: ByteFormat.string(Int64(lifetimeBytes)))
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))

                if let error = result.contactsError {
                    Label("Contacts weren't deleted: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if result.photosDeleted + result.videosDeleted > 0 {
                    Label("Removed photos and videos are in Recently Deleted in the Photos app for 30 days. To get the space back now, open Photos › Recently Deleted and choose Delete All.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .task {
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 1.0)) { shownBytes = result.bytesFreed }
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding()
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 56)
        }
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
