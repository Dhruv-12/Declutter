import SwiftUI

/// Home: how much you can free, where your storage goes, and one row per category.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reviewPlan: CleanupPlan?

    /// The number in the headline. Normally the live value; counts down after a cleanup.
    @State private var shownReclaimable: Double?
    /// Bytes from the latest cleanup, drawn as their own piece of the bar while it animates.
    @State private var animatingChunk: Int64 = 0
    /// 0: the chunk still looks like cleanable space. 1: it has turned Mint and slid out.
    @State private var chunkProgress: Double = 1

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing * 1.5) {
                    hero
                    PermissionBanners()
                    categories
                    Label("Everything is checked on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.page)
                .padding(.vertical, Theme.spacing)
            }
            .screenBackground()
            .navigationTitle("Declutter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CleanupCategory.self) { category in
                destination(for: category)
            }
            .refreshable {
                model.refreshPermissions()
                await model.reloadLibrary()
            }
            .safeAreaInset(edge: .bottom) {
                SelectionBar(count: model.selectedCount, bytes: model.selectedBytes) {
                    reviewPlan = model.makePlan()
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .onChange(of: model.freedEvent) { _, event in
                if let event { Task { await playFreedAnimation(event) } }
            }
        }
    }

    // MARK: - Headline and storage bar

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 0) {
                CountingBytes(value: shownReclaimable ?? Double(model.reclaimableBytes))
                    .font(.heroNumber)
                    .foregroundStyle(Theme.pine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("you can free")
                    .font(.heading(.title3))
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)

            if let storage = model.storage {
                StorageBar(
                    storage: storage,
                    cleanable: model.reclaimableBytes,
                    freedEarlier: model.freedThisSession - animatingChunk,
                    chunk: animatingChunk,
                    chunkProgress: chunkProgress
                )
            }

            if model.similar.isScanning {
                Label("Still looking for similar photos…", systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The one big animation: the freed chunk turns Mint and slides out of the cleanable space,
    /// while the headline counts down. With Reduce Motion, everything just updates.
    private func playFreedAnimation(_ event: FreedEvent) async {
        model.freedEvent = nil
        guard !reduceMotion else {
            shownReclaimable = nil
            animatingChunk = 0
            chunkProgress = 1
            return
        }
        shownReclaimable = Double(event.reclaimableBefore)
        animatingChunk = event.bytes
        chunkProgress = 0

        // Let the review sheet finish closing so the moment is seen.
        try? await Task.sleep(for: .milliseconds(550))
        withAnimation(.easeInOut(duration: 0.7)) { chunkProgress = 1 }
        withAnimation(.easeOut(duration: 1.3)) { shownReclaimable = Double(model.reclaimableBytes) }
        try? await Task.sleep(for: .milliseconds(1300))
        Haptics.success()
        animatingChunk = 0
        shownReclaimable = nil
    }

    // MARK: - Categories

    private var categories: some View {
        VStack(alignment: .leading, spacing: Theme.gap + 4) {
            Text("Clean up")
                .font(.heading(.title3))
                .foregroundStyle(Theme.pine)
            VStack(spacing: 0) {
                ForEach(CleanupCategory.allCases) { category in
                    NavigationLink(value: category) {
                        CategoryRow(category: category, summary: model.summary(for: category))
                    }
                    .buttonStyle(.plain)
                    if category != CleanupCategory.allCases.last {
                        Theme.hairline.frame(height: 1).padding(.leading, 72)
                    }
                }
            }
            .background(Theme.stone, in: .rect(cornerRadius: Theme.radius))
        }
    }

    @ViewBuilder private func destination(for category: CleanupCategory) -> some View {
        switch category {
        case .screenshots:
            ScreenshotsView()
        case .largeVideos:
            LargeVideosView()
        case .similarPhotos:
            SimilarPhotosView()
        case .duplicateContacts:
            DuplicateContactsView()
        }
    }
}

/// Text that counts smoothly between two byte values when animated.
private struct CountingBytes: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(ByteFormat.string(Int64(max(value, 0))))
            .monospacedDigit()
    }
}

/// Wide horizontal bar: used, cleanable, freed and free space.
struct StorageBar: View {
    let storage: DeviceStorage
    let cleanable: Int64
    /// Freed by earlier cleanups this session (still in Recently Deleted).
    let freedEarlier: Int64
    /// Freed by the cleanup that is animating right now.
    let chunk: Int64
    let chunkProgress: Double

    private var total: Double { Double(max(storage.total, 1)) }
    private var freed: Int64 { max(freedEarlier, 0) + chunk }
    private var cleanableShown: Int64 { min(cleanable, max(storage.used - freed, 0)) }
    private var otherUsed: Int64 { max(storage.used - cleanableShown - freed, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let other = width * CGFloat(Double(otherUsed) / total)
                let cleanableWidth = segment(cleanableShown, in: width)
                let earlierWidth = segment(max(freedEarlier, 0), in: width)
                let chunkWidth = segment(chunk, in: width)
                let gap: CGFloat = 4

                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stone)

                    HStack(spacing: 0) {
                        Rectangle().fill(Theme.pine).frame(width: other)
                        Rectangle().fill(Theme.pine.opacity(0.4)).frame(width: cleanableWidth)
                    }
                    .clipShape(Capsule())

                    // Space freed earlier: Mint, just past the cleanable part.
                    if earlierWidth > 0 {
                        Capsule()
                            .fill(Theme.mint)
                            .frame(width: earlierWidth)
                            .offset(x: other + cleanableWidth + gap + chunkWidth)
                    }

                    // The chunk from this cleanup starts as cleanable space, then turns Mint and slides out.
                    if chunkWidth > 0 {
                        Capsule()
                            .fill(Theme.pine.opacity(0.4))
                            .overlay(Capsule().fill(Theme.mint).opacity(chunkProgress))
                            .frame(width: chunkWidth)
                            .offset(x: other + cleanableWidth + gap * chunkProgress)
                    }
                }
            }
            .frame(height: 22)
            .accessibilityElement()
            .accessibilityLabel("Storage")
            .accessibilityValue(accessibilityText)

            legend
        }
    }

    /// Tiny amounts still get a visible sliver.
    private func segment(_ bytes: Int64, in width: CGFloat) -> CGFloat {
        guard bytes > 0 else { return 0 }
        return max(width * CGFloat(Double(bytes) / total), 4)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legendItems }
                VStack(alignment: .leading, spacing: 4) { legendItems }
            }
            Text(freed > 0
                 ? "Of \(ByteFormat.string(storage.total)). Freed space is fully cleared when Recently Deleted empties."
                 : "Of \(ByteFormat.string(storage.total)) on this iPhone.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var legendItems: some View {
        LegendItem(color: Theme.pine, title: "Used", value: otherUsed)
        LegendItem(color: Theme.pine.opacity(0.4), title: "Can free", value: cleanableShown)
        if freed > 0 {
            LegendItem(color: Theme.mint, title: "Freed", value: freed)
        }
        LegendItem(color: Theme.stone, title: "Free", value: storage.available, outlined: true)
    }

    private var accessibilityText: String {
        var parts = [
            "\(ByteFormat.string(otherUsed)) used",
            "\(ByteFormat.string(cleanableShown)) can be freed",
        ]
        if freed > 0 { parts.append("\(ByteFormat.string(freed)) freed") }
        parts.append("\(ByteFormat.string(storage.available)) free of \(ByteFormat.string(storage.total))")
        return parts.joined(separator: ", ")
    }
}

private struct LegendItem: View {
    let color: Color
    let title: String
    let value: Int64
    var outlined = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .overlay { if outlined { Circle().strokeBorder(Theme.hairline, lineWidth: 1) } }
                .frame(width: 10, height: 10)
            Text(title)
                .foregroundStyle(Theme.secondaryText)
            Text(ByteFormat.string(value))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.pine)
        }
        .font(.caption)
        .fixedSize()
    }
}

/// One category on the home screen: icon, name, count and size.
struct CategoryRow: View {
    let category: CleanupCategory
    let summary: CategorySummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.pine)
                .frame(width: 42, height: 42)
                .background(Theme.mist, in: .rect(cornerRadius: Theme.smallRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 8)

            trailing

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    private var detail: String {
        switch summary {
        case .needsAccess: category.needsPhotos ? "Needs Photos access" : "Needs Contacts access"
        case .loading: "Counting…"
        case .scanning(let progress): "Scanning… \(Int(progress * 100))%"
        case .notScanned: "Tap to scan"
        case .ready(let count, _):
            switch category {
            case .screenshots: count == 1 ? "1 screenshot" : "\(count) screenshots"
            case .largeVideos: count == 1 ? "1 video" : "\(count) videos"
            case .similarPhotos: count == 1 ? "1 extra photo" : "\(count) extra photos"
            case .duplicateContacts: count == 1 ? "1 duplicate" : "\(count) duplicates"
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch summary {
        case .loading:
            ProgressView()
        case .scanning(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
        case .ready(_, let bytes?):
            Text(ByteFormat.string(bytes))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.pine)
        case .needsAccess:
            Image(systemName: "lock.fill")
                .foregroundStyle(Theme.secondaryText)
        default:
            EmptyView()
        }
    }
}
