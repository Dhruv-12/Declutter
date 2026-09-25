import Photos
import SwiftUI

/// Every screenshot in one grid, grouped by month, with multi-select.
struct ScreenshotsView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    private var items: [MediaItem] { model.screenshots }

    private var selection: Set<String> { model.screenshotSelection }

    var body: some View {
        @Bindable var model = model
        return content
            .navigationTitle("Screenshots")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SelectAllButton(allIDs: items.map(\.id), selection: $model.screenshotSelection)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty {
                    SelectionBar(count: selection.count, bytes: selectedBytes, actionTitle: "Review") {
                        reviewPlan = model.makePlan(for: [.screenshots])
                    }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selection.isEmpty)
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else if model.isLoadingLibrary && items.isEmpty {
            ProgressView("Finding screenshots…")
        } else if items.isEmpty {
            ContentUnavailableView(
                "No Screenshots",
                systemImage: "camera.viewfinder",
                description: Text("There are no screenshots to clean up.")
            )
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            Text("\(items.count) screenshots · \(ByteFormat.string(items.totalSize))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 4, pinnedViews: .sectionHeaders) {
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
            .padding(.horizontal, 4)
        }
    }

    private func toggle(_ id: String) {
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
            Text(title).font(.headline)
            Spacer()
            SelectAllButton(allIDs: ids, selection: $selection)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
