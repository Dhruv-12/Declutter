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
                if !model.videos.isEmpty && model.photoStatus.canRead {
                    SelectionBar(count: selection.count, bytes: selectedBytes, singular: "video", plural: "videos") {
                        reviewPlan = model.makePlan(for: [.largeVideos])
                    }
                }
            }
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
            LoadingView(text: "Finding videos…")
        } else if items.isEmpty {
            if minimumSize == .all {
                EmptyStateView(
                    systemImage: "play.rectangle",
                    title: "No videos",
                    message: "There are no videos on this iPhone. Videos you record will show up here, biggest first."
                )
            } else {
                EmptyStateView(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "No videos \(minimumSize.title.lowercased())",
                    message: "Try a smaller size to see more videos.",
                    actionTitle: "Show all videos"
                ) {
                    minimumSize = .all
                }
            }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            ScreenSummary(
                text: "\(items.count) videos · \(ByteFormat.string(items.totalSize))",
                detail: "Biggest first. Tap a thumbnail to play it."
            )
            .padding(.top, Theme.gap)

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
            .padding(.bottom, Theme.gap)

            LazyVStack(spacing: Theme.gap + 2) {
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
            .padding(.horizontal, Theme.page)
            .padding(.bottom, Theme.spacing)
        }
        .screenBackground()
    }

    private func toggle(_ id: String) {
        Haptics.select()
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
        self == .all ? "All videos" : "Over \(ByteFormat.string(rawValue))"
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
                    .frame(width: 100, height: 72)
                    .clipShape(.rect(cornerRadius: Theme.smallRadius))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.onPine)
                            .frame(width: 32, height: 32)
                            .background(Theme.pine.opacity(0.85), in: .circle)
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

            VStack(alignment: .leading, spacing: 6) {
                Text(ByteFormat.string(item.size))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.pine)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                // How this video compares with the biggest one.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.mist)
                        Capsule().fill(Theme.pine.opacity(0.4))
                            .frame(width: max(geometry.size.width * fractionOfLargest, 4))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }

            SelectionCheckmark(isSelected: isSelected)
        }
        .padding(12)
        .background(Theme.stone, in: .rect(cornerRadius: Theme.radius))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.pine, lineWidth: 2)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
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
                    VStack(spacing: Theme.gap) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("This video can't be played")
                            .font(.heading(.headline))
                        Text("It may still be downloading from iCloud. Try again in a moment.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(Theme.page)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .navigationTitle(ByteFormat.string(item.size))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSelected ? "Deselect video" : "Select video") {
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
