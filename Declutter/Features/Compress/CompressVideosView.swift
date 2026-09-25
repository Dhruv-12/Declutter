import Photos
import SwiftUI

/// Every video, largest first. Pick one to make a smaller copy.
struct CompressVideosView: View {
    @Environment(AppModel.self) private var model
    @State private var compressing: MediaItem?

    private var compress: CompressVideosModel { model.compress }

    var body: some View {
        content
            .navigationTitle("Compress videos")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $compressing) { item in
                CompressSheet(original: item)
            }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else if model.isLoadingLibrary && model.videos.isEmpty {
            LoadingView(text: "Finding videos…")
        } else if model.videos.isEmpty {
            EmptyStateView(
                systemImage: "play.rectangle",
                title: "No videos",
                message: "There are no videos on this iPhone to compress."
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ScreenSummary(
                    text: "Pick a video to make a smaller copy",
                    detail: "The copy is saved to Photos next to the original. The original stays until you choose to delete it."
                )
                if compress.totalSaved > 0 {
                    Label("Saved \(ByteFormat.string(compress.totalSaved)) by compressing", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.mintText)
                        .padding(.horizontal, Theme.page)
                        .accessibilityIdentifier("compress.saved")
                }
            }
            .padding(.top, Theme.gap)

            LazyVStack(spacing: Theme.gap + 2) {
                ForEach(model.videos) { item in
                    Button {
                        Haptics.select()
                        compressing = item
                    } label: {
                        CompressRow(item: item, isCopy: compress.copyIDs.contains(item.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("compressRow")
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.vertical, Theme.spacing)
        }
        .screenBackground()
    }
}

private struct CompressRow: View {
    let item: MediaItem
    let isCopy: Bool

    var body: some View {
        HStack(spacing: 14) {
            AssetThumbnail(asset: item.asset)
                .frame(width: 88, height: 64)
                .clipShape(.rect(cornerRadius: Theme.thumbRadius))
                .overlay(alignment: .bottomTrailing) {
                    Text(item.asset.duration.durationText)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
                        .padding(4)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(ByteFormat.string(item.size))
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.pine)
                Text("\(item.asset.pixelWidth)×\(item.asset.pixelHeight)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                if isCopy {
                    Text("Compressed copy")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.onPine)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.pineFill, in: .capsule)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(12)
        .surface()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Choose a quality, compress, save the copy, then optionally review deleting the original.
struct CompressSheet: View {
    let original: MediaItem

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Step: Equatable {
        case loading
        case choosing
        case compressing(progress: Double)
        case saving
        case done(copyBytes: Int64)
        case failed(String)
    }

    @State private var step: Step = .loading
    @State private var source: VideoSource?
    @State private var options: [CompressionOption] = []
    @State private var chosen: CompressionQuality?
    @State private var job: Task<Void, Never>?
    @State private var reviewPlan: CleanupPlan?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing * 1.5) {
                    header
                    stepContent
                }
                .padding(Theme.page)
            }
            .screenBackground()
            .navigationTitle("Compress video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isWorking ? "Stop" : "Close") {
                        job?.cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("compress.close")
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .interactiveDismissDisabled(isWorking)
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .task { await prepare() }
        }
    }

    private var isWorking: Bool {
        switch step {
        case .compressing, .saving: true
        default: false
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AssetThumbnail(asset: original.asset)
                .frame(width: 96, height: 72)
                .clipShape(.rect(cornerRadius: Theme.thumbRadius))
            VStack(alignment: .leading, spacing: 4) {
                Text(ByteFormat.string(original.size))
                    .font(.bigNumber)
                    .foregroundStyle(Theme.pine)
                Text("\(original.asset.pixelWidth)×\(original.asset.pixelHeight) · \(original.asset.duration.durationText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .loading:
            HStack(spacing: Theme.gap) {
                ProgressView().tint(Theme.pine)
                Text("Checking quality options…")
                    .foregroundStyle(Theme.secondaryText)
            }
        case .choosing:
            qualityPicker
        case .compressing(let progress):
            progressView(progress, title: "Compressing", note: "Keep Declutter open until it finishes.")
        case .saving:
            progressView(1, title: "Saving the copy to Photos", note: "")
        case .done(let copyBytes):
            doneView(copyBytes)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.coralText)
        }
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: Theme.gap + 4) {
            Text("Choose a quality")
                .font(.heading(.title3))
                .foregroundStyle(Theme.pine)
            if options.isEmpty {
                Text("This video can't be compressed on this iPhone.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(options) { option in
                let saving = option.estimatedBytes.flatMap { CompressionMath.saving(original: original.size, copy: $0) }
                let worthIt = option.estimatedBytes == nil || saving != nil
                Button {
                    Haptics.select()
                    chosen = option.quality
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: chosen == option.quality ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(chosen == option.quality ? Theme.pine : Theme.secondaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.quality.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.pine)
                            Text(option.quality.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Text(estimateText(option, saving: saving))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(saving != nil ? Theme.mintText : Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .card()
                    .overlay {
                        if chosen == option.quality {
                            RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.pine, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!worthIt)
                .opacity(worthIt ? 1 : 0.5)
                .accessibilityIdentifier("quality.\(option.quality.rawValue)")
                .accessibilityAddTraits(chosen == option.quality ? .isSelected : [])
            }
        }
    }

    private func estimateText(_ option: CompressionOption, saving: Int64?) -> String {
        guard let estimate = option.estimatedBytes else { return "Size shown after compressing" }
        guard let saving else { return "About \(ByteFormat.string(estimate)): won't save space" }
        return "About \(ByteFormat.string(estimate)) · saves \(ByteFormat.string(saving))"
    }

    private func progressView(_ progress: Double, title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.heroNumber)
                .monospacedDigit()
                .foregroundStyle(Theme.pine)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stone)
                    Capsule().fill(Theme.barUsed)
                        .frame(width: max(geometry.size.width * progress, 22))
                }
            }
            .frame(height: 22)
            Text(title).font(.heading(.title3)).foregroundStyle(Theme.pine)
            if !note.isEmpty {
                Text(note).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func doneView(_ copyBytes: Int64) -> some View {
        let saving = max(original.size - copyBytes, 0)
        return VStack(alignment: .leading, spacing: Theme.spacing) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onMint)
                .frame(width: 56, height: 56)
                .background(Theme.mint, in: .circle)
                .accessibilityHidden(true)
            Text("Saved a \(ByteFormat.string(copyBytes)) copy to Photos")
                .font(.heading(.title3))
                .foregroundStyle(Theme.pine)
                .accessibilityIdentifier("compress.done")
            Text("Deleting the original frees \(ByteFormat.string(saving)). The copy has the same date and place, so it sits in the same spot in your library.")
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var bottomBar: some View {
        Group {
            switch step {
            case .choosing:
                Button("Compress video") { start() }
                    .buttonStyle(.primary)
                    .disabled(chosen == nil)
                    .accessibilityIdentifier("compress.start")
            case .done:
                VStack(spacing: Theme.gap) {
                    Button("Review and delete original") {
                        reviewPlan = model.makeCompressPlan(original: original)
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("compress.reviewOriginal")
                    Button("Keep both") { dismiss() }
                        .buttonStyle(.secondary)
                        .accessibilityIdentifier("compress.keepBoth")
                }
            case .failed:
                Button("Try again") { Task { await prepare() } }
                    .buttonStyle(.primary)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, Theme.page)
        .padding(.vertical, 12)
        .background(Theme.mist.ignoresSafeArea())
    }

    // MARK: - Work

    private func prepare() async {
        step = .loading
        guard let loaded = await VideoCompressor.load(original.asset) else {
            step = .failed(CompressionError.unavailable.localizedDescription)
            return
        }
        source = loaded
        options = await VideoCompressor.options(for: loaded)
        // Preselect the first quality that would actually save space.
        chosen = options.first { option in
            option.estimatedBytes.map { CompressionMath.saving(original: original.size, copy: $0) != nil } ?? true
        }?.quality
        step = .choosing
    }

    private func start() {
        guard let source, let quality = chosen else { return }
        Haptics.confirm()
        step = .compressing(progress: 0)
        job = Task {
            do {
                let url = try await VideoCompressor.export(source, quality: quality) { progress in
                    if case .compressing = step { step = .compressing(progress: progress) }
                }
                let copyBytes = VideoCompressor.fileSize(url)
                step = .saving
                let copyID = try await VideoCompressor.saveToPhotos(url, like: original.asset)
                model.compress.add(CompressionRecord(
                    originalID: original.id, copyID: copyID,
                    originalBytes: original.size, copyBytes: copyBytes
                ))
                Haptics.success()
                step = .done(copyBytes: copyBytes)
            } catch is CancellationError {
                step = .choosing
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }
}
