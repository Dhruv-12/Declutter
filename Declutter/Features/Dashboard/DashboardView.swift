import SwiftUI

/// Home: how much you can free, where your storage goes, and one row per category.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
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
                VStack(alignment: .leading, spacing: Theme.spacing * 2) {
                    hero
                    PermissionBanners()
                    categories
                    tools
                    Label("Everything is checked on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Theme.page)
                .padding(.top, Theme.gap)
                .padding(.bottom, Theme.spacing * 2)
            }
            .screenBackground()
            .navigationTitle("Declutter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CleanupCategory.self) { category in
                destination(for: category)
            }
            .navigationDestination(for: Tool.self) { tool in
                destination(for: tool)
            }
            .refreshable {
                model.refreshPermissions()
                await model.reloadLibrary()
            }
            .safeAreaInset(edge: .bottom) {
                SelectionBar(count: model.selectedCount, bytes: model.selectedBytes) {
                    reviewPlan = model.makeHomePlan()
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
        VStack(alignment: .leading, spacing: Theme.spacing + 4) {
            VStack(alignment: .leading, spacing: 2) {
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
                    .accessibilityIdentifier("category.\(category.rawValue)")
                    if category != CleanupCategory.allCases.last {
                        Theme.hairline.frame(height: 1).padding(.leading, 74)
                    }
                }
            }
            .surface()
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: Theme.gap + 4) {
            Text("Tools")
                .font(.heading(.title3))
                .foregroundStyle(Theme.pine)
            // Two tiles per row; one per row with very large text, so names aren't split mid-word.
            let columns = typeSize.isAccessibilitySize ? 1 : 2
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(Tool.allCases) { tool in
                    NavigationLink(value: tool) {
                        ToolTile(tool: tool, detail: toolDetail(tool))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tool.\(tool.rawValue)")
                }
            }
        }
    }

    /// A live line on a tile, once there is something to report.
    private func toolDetail(_ tool: Tool) -> String? {
        switch tool {
        case .swipe:
            let marked = model.swipe.marked
            return marked.isEmpty ? nil : "\(counted(marked.count, "photo")) marked"
        case .blurry:
            switch model.blurry.state {
            case .idle: return nil
            case .scanning(let progress): return "Scanning… \(Int(progress * 100))%"
            case .done:
                let photos = model.blurry.items
                return photos.isEmpty ? "None found" : "\(counted(photos.count, "photo")) · \(ByteFormat.string(photos.totalSize))"
            }
        case .compress:
            let compress = model.compress
            if compress.totalSaved > 0 { return "Saved \(ByteFormat.string(compress.totalSaved))" }
            return compress.records.isEmpty ? nil : "\(counted(compress.records.count, "video")) compressed"
        case .widget:
            return nil
        case .vault:
            switch model.vault.state {
            case .needsSetup: return nil
            case .locked: return "Locked"
            case .unlocked: return "\(counted(model.vault.items.count, "photo")) · unlocked"
            }
        }
    }

    @ViewBuilder private func destination(for tool: Tool) -> some View {
        switch tool {
        case .swipe:
            SwipeSortView()
        case .blurry:
            BlurryPhotosView()
        case .compress:
            CompressVideosView()
        case .widget:
            WidgetGuideView()
        case .vault:
            VaultView()
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

/// Wide horizontal bar: used, cleanable, freed and free space, in one smooth rounded track.
struct StorageBar: View {
    let storage: DeviceStorage
    let cleanable: Int64
    /// Freed by earlier cleanups this session (still in Recently Deleted).
    let freedEarlier: Int64
    /// Freed by the cleanup that is animating right now.
    let chunk: Int64
    let chunkProgress: Double

    private var total: Double { Double(max(storage.total, 1)) }
    private var breakdown: StorageBreakdown {
        StorageBreakdown(storage: storage, cleanable: cleanable, freed: max(freedEarlier, 0) + chunk)
    }
    private var freed: Int64 { breakdown.freed }
    private var cleanableShown: Int64 { breakdown.cleanable }
    private var otherUsed: Int64 { breakdown.otherUsed }

    /// Thin gap between segments, showing the track through.
    private let gap: CGFloat = 2
    /// How far the freed chunk slides out while it turns Mint.
    private let slide: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let usedWidth = width * CGFloat(Double(otherUsed) / total)
                let cleanableWidth = segment(cleanableShown, in: width)
                let chunkWidth = segment(chunk, in: width)
                let earlierWidth = segment(max(freedEarlier, 0), in: width)
                let cleanableX = usedWidth + (cleanableWidth > 0 ? gap : 0)
                let chunkX = cleanableX + cleanableWidth + gap
                let earlierX = chunkX + (chunkWidth > 0 ? chunkWidth + gap : 0) + slide

                ZStack(alignment: .leading) {
                    Theme.barTrack
                    Theme.barUsed.frame(width: usedWidth)
                    Theme.barCleanable
                        .frame(width: cleanableWidth)
                        .offset(x: cleanableX)
                    if earlierWidth > 0 {
                        Capsule()
                            .fill(Theme.mint)
                            .frame(width: earlierWidth)
                            .offset(x: earlierX)
                    }
                    // This cleanup's chunk starts as cleanable space, then turns Mint and slides out.
                    if chunkWidth > 0 {
                        Capsule()
                            .fill(Theme.barCleanable)
                            .overlay(Capsule().fill(Theme.mint).opacity(chunkProgress))
                            .frame(width: chunkWidth)
                            .offset(x: chunkX - gap + (gap + slide) * chunkProgress)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 20)
            .overlay { Capsule().strokeBorder(Theme.cardBorder, lineWidth: 1) }
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
        LegendItem(color: Theme.barUsed, title: "Used", value: otherUsed)
        LegendItem(color: Theme.barCleanable, title: "Can free", value: cleanableShown)
        if freed > 0 {
            LegendItem(color: Theme.mint, title: "Freed", value: freed)
        }
        LegendItem(color: Theme.barTrack, title: "Free", value: storage.available, outlined: true)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Very large text: stack the row so the name gets the full width.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        icon
                        Spacer()
                        chevron
                    }
                    titles
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 14) {
                    icon
                    titles
                    Spacer(minLength: 8)
                    trailing
                    chevron
                }
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(category.title.lowercased())")
    }

    private var icon: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .tintedCircle(category.tint)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(category.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.pine)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
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
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.pine)
        case .needsAccess:
            Image(systemName: "lock.fill")
                .foregroundStyle(Theme.secondaryText)
        default:
            EmptyView()
        }
    }
}

/// A tool on the home screen: colour icon, name and a short line about what it does.
struct ToolTile: View {
    let tool: Tool
    /// Live status, such as "12 photos · 40 MB"; replaces the description when set.
    var detail: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .tintedCircle(tool.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                Text(detail ?? tool.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    // Two lines keep the grid even; one tile per row with big text, so no limit there.
                    .lineLimit(typeSize.isAccessibilitySize ? 6 : 2, reservesSpace: !typeSize.isAccessibilitySize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .surface()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
