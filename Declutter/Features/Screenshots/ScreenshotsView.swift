import Photos
import SwiftUI

/// Every screenshot in one grid, grouped by month, with multi-select.
struct ScreenshotsView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    private var items: [MediaItem] { model.screenshots }

    private var selection: Set<String> { model.screenshotSelection }

    var body: some View {
        content
            .navigationTitle("Screenshots")
            .safeAreaInset(edge: .bottom) {
                if !items.isEmpty {
                    SelectionBar(count: selection.count, bytes: selectedBytes, singular: "screenshot", plural: "screenshots") {
                        reviewPlan = model.makePlan(for: [.screenshots])
                    }
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else if model.isLoadingLibrary && items.isEmpty {
            LoadingView(text: "Finding screenshots…")
        } else if items.isEmpty {
            EmptyStateView(
                systemImage: "camera.viewfinder",
                title: "No screenshots",
                message: "Nothing to clear here. New screenshots will show up on this screen."
            )
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            ScreenSummary(text: "\(items.count) screenshots · \(ByteFormat.string(items.totalSize))")
                .padding(.top, Theme.gap)

            BulkActionBar {
                let allSelected = items.allSatisfy { selection.contains($0.id) }
                BulkActionButton(
                    title: allSelected ? "Deselect all" : "Select all",
                    count: items.count,
                    bytes: items.totalSize,
                    systemImage: allSelected ? "circle" : "checkmark.circle"
                ) {
                    model.screenshotSelection = allSelected ? [] : Set(items.map(\.id))
                }
                BulkActionButton(
                    title: "Review and delete all",
                    count: items.count,
                    bytes: items.totalSize,
                    systemImage: "trash",
                    role: .destructive
                ) {
                    // Opens the review screen; nothing is deleted until the user confirms there.
                    reviewPlan = model.makeDeleteAllPlan(.screenshots)
                }
            }
            .padding(.bottom, Theme.gap)

            LazyVGrid(columns: columns, spacing: 6, pinnedViews: .sectionHeaders) {
                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.items) { item in
                            SelectableThumbnail(asset: item.asset, isSelected: selection.contains(item.id))
                                .aspectRatio(9 / 16, contentMode: .fit)
                                .onTapGesture { toggle(item.id) }
                                .contextMenu {
                                    Button(selection.contains(item.id) ? "Deselect" : "Select",
                                           systemImage: selection.contains(item.id) ? "circle" : "checkmark.circle") {
                                        toggle(item.id)
                                    }
                                } preview: {
                                    AssetThumbnail(asset: item.asset, contentMode: .fit)
                                        .frame(width: 300, height: 540)
                                }
                        }
                    } header: {
                        SectionHeader(
                            title: section.title,
                            ids: section.items.map(\.id),
                            selection: Binding(get: { model.screenshotSelection }, set: { model.screenshotSelection = $0 })
                        )
                    }
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
            model.screenshotSelection.remove(id)
        } else {
            model.screenshotSelection.insert(id)
        }
    }

    private var selectedBytes: Int64 {
        items.filter { selection.contains($0.id) }.totalSize
    }

    /// Screenshots grouped by the month they were taken, newest first.
    private var sections: [(title: String, items: [MediaItem])] {
        var result: [(title: String, items: [MediaItem])] = []
        for item in items {
            let title = item.asset.creationDate?.formatted(.dateTime.month(.wide).year()) ?? "Unknown Date"
            if result.last?.title == title {
                result[result.count - 1].items.append(item)
            } else {
                result.append((title, [item]))
            }
        }
        return result
    }
}

private struct SectionHeader: View {
    let title: String
    let ids: [String]
    @Binding var selection: Set<String>

    var body: some View {
        HStack {
            Text(title)
                .font(.heading(.headline))
                .foregroundStyle(Theme.pine)
            Spacer()
            SelectAllButton(allIDs: ids, selection: $selection)
        }
        .padding(.vertical, 10)
        .background(Theme.mist)
    }
}
