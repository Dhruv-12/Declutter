import AVKit
import Photos
import SwiftUI

/// All videos from largest to smallest, with a preview player and multi-select.
struct LargeVideosView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?
    @State private var minimumSize: SizeFilter = .all
    @State private var previewing: MediaItem?

    /// Videos are already sorted largest first by the loader.
    private var items: [MediaItem] {
        model.videos.filter { $0.size >= minimumSize.bytes }
    }

    private var selection: Set<String> { model.videoSelection }

    var body: some View {
        content
            .navigationTitle("Large Videos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Show", selection: $minimumSize) {
                            ForEach(SizeFilter.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Filter", systemImage: minimumSize == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty {
                    SelectionBar(count: selection.count, bytes: selectedBytes, actionTitle: "Review") {
                        reviewPlan = model.makePlan(for: [.largeVideos])
                    }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection.isEmpty)
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .sheet(item: $previewing) { item in
                VideoPreviewView(
                    item: item,
                    isSelected: selection.contains(item.id),
                    onToggle: { toggle(item.id) }
                )
            }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else if model.isLoadingLibrary && model.videos.isEmpty {
            ProgressView("Finding videos…")
        } else if items.isEmpty {
            ContentUnavailableView(
                "No Videos",
                systemImage: "play.rectangle",
                description: Text(minimumSize == .all
                                  ? "There are no videos on this iPhone."
                                  : "No videos are \(minimumSize.title.lowercased()).")
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            Text("\(items.count) videos · \(ByteFormat.string(items.totalSize))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            BulkActionBar {
                let allSelected = items.allSatisfy { selection.contains($0.id) }
                BulkActionButton(
                    title: allSelected ? "Deselect all" : "Select all",
                    count: items.count,
                    bytes: items.totalSize,
                    systemImage: allSelected ? "circle" : "checkmark.circle"
                ) {
                    let ids = items.map(\.id)
                    if allSelected {
                        model.videoSelection.subtract(ids)
                    } else {
                        model.videoSelection.formUnion(ids)
                    }
                }
            }
            .padding(.bottom, 4)

            LazyVStack(spacing: 10) {
                let largest = max(items.first?.size ?? 1, 1)
                ForEach(items) { item in
                    VideoRow(
                        item: item,
                        fractionOfLargest: Double(item.size) / Double(largest),
                        isSelected: selection.contains(item.id),
                        onPreview: { previewing = item }
                    )
                    .onTapGesture { toggle(item.id) }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            model.videoSelection.remove(id)
        } else {
            model.videoSelection.insert(id)
        }
    }

    private var selectedBytes: Int64 {
        model.videos.filter { selection.contains($0.id) }.totalSize
    }
}

enum SizeFilter: Int64, CaseIterable, Identifiable {
    case all = 0
    case over50MB = 50_000_000
    case over100MB = 100_000_000
    case over500MB = 500_000_000

    var id: Int64 { rawValue }
    var bytes: Int64 { rawValue }

    var title: String {
        self == .all ? "All Videos" : "Over \(ByteFormat.string(rawValue))"
    }
}

private struct VideoRow: View {
    let item: MediaItem
    let fractionOfLargest: Double
    let isSelected: Bool
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPreview) {
                AssetThumbnail(asset: item.asset)
                    .frame(width: 100, height: 70)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(item.asset.duration.durationText)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55), in: .rect(cornerRadius: 4))
                            .padding(4)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview video")

            VStack(alignment: .leading, spacing: 4) {
                Text(ByteFormat.string(item.size))
                    .font(.headline)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: fractionOfLargest)
                    .tint(CleanupCategory.largeVideos.tint)
            }

            SelectionCheckmark(isSelected: isSelected)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(.rect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var details: String {
        var parts: [String] = []
        if let date = item.asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("\(item.asset.pixelWidth)×\(item.asset.pixelHeight)")
        return parts.joined(separator: " · ")
    }
}

/// Full-screen player for checking a video before choosing to remove it.
struct VideoPreviewView: View {
    let item: MediaItem
    let isSelected: Bool
    let onToggle: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    VideoPlayer(player: player)
                } else if failed {
                    ContentUnavailableView("Can't Play Video", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle(ByteFormat.string(item.size))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSelected ? "Deselect" : "Select") {
                        onToggle()
                        dismiss()
                    }
                }
            }
        }
        .task {
            guard let playerItem = await VideoLoader.playerItem(for: item.asset) else {
                failed = true
                return
            }
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}

enum VideoLoader {
    static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true  // Needed if the original is stored in iCloud.
        options.deliveryMode = .automatic
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                continuation.resume(returning: playerItem)
            }
        }
    }
}

extension TimeInterval {
    /// "0:42", "12:05" or "1:03:10".
    var durationText: String {
        let duration = Duration.seconds(self)
        return self >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }
}
