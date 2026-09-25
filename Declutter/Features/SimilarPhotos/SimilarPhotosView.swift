import Photos
import SwiftUI

/// Groups of similar photos. The best shot in each group is kept; the rest are pre-selected.
struct SimilarPhotosView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?

    private var similar: SimilarPhotosModel { model.similar }

    var body: some View {
        content
            .navigationTitle("Similar photos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .safeAreaInset(edge: .bottom) {
                if similar.state == .done && !similar.groups.isEmpty && model.photoStatus.canRead {
                    SelectionBar(count: similar.selection.count, bytes: similar.selectedItems.totalSize, singular: "photo", plural: "photos") {
                        reviewPlan = model.makePlan(for: [.similarPhotos])
                    }
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .onAppear {
                if similar.state == .idle && model.photoStatus.canRead { similar.scan() }
            }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else {
            switch similar.state {
            case .idle:
                EmptyStateView(
                    systemImage: "square.on.square",
                    title: "Find similar photos",
                    message: "Declutter compares your photos on this iPhone and keeps the best shot from each set.",
                    actionTitle: "Scan photos"
                ) {
                    similar.scan()
                }
            case .scanning(let progress):
                ScanProgressView(progress: progress)
            case .done:
                if similar.groups.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.seal",
                        title: "No similar photos",
                        message: "Checked \(similar.scannedCount) photos and none look alike. Your library is tidy.",
                        actionTitle: "Scan again"
                    ) {
                        similar.scan()
                    }
                } else {
                    groupList
                }
            }
        }
    }

    private var groupList: some View {
        ScrollView {
            Color.clear.frame(height: 0)
                .onAppear { similar.resultsShown() }

            ScreenSummary(
                text: "\(similar.groups.count) sets · \(similar.extras.count) extra photos · \(ByteFormat.string(similar.extras.totalSize))",
                detail: similar.scanDuration.map {
                    "Checked \(similar.scannedCount) photos in \($0.formatted(.number.precision(.fractionLength(1)))) s, on this iPhone. Long-press a photo to keep it instead."
                }
            )
            .padding(.top, Theme.gap)

            BulkActionBar {
                let extras = similar.extras
                let allSelected = extras.allSatisfy { similar.selection.contains($0.id) }
                BulkActionButton(
                    title: allSelected ? "Deselect all duplicates" : "Select all duplicates",
                    count: extras.count,
                    bytes: extras.totalSize,
                    systemImage: allSelected ? "circle" : "checkmark.circle"
                ) {
                    similar.selectAllExtras(!allSelected)
                }
            }
            .padding(.vertical, Theme.gap)

            LazyVStack(spacing: Theme.spacing) {
                ForEach(similar.groups) { group in
                    SimilarGroupCard(group: group, similar: similar)
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, Theme.spacing)
        }
        .screenBackground()
    }

    private var optionsMenu: some View {
        Menu {
            Button("Scan again", systemImage: "arrow.clockwise") { similar.scan() }
            Picker(selection: Binding(get: { similar.strictness }, set: { similar.strictness = $0 })) {
                ForEach(MatchStrictness.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("How close a match", systemImage: "slider.horizontal.3")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
        .disabled(!model.photoStatus.canRead)
    }
}

private struct SimilarGroupCard: View {
    let group: SimilarGroup
    let similar: SimilarPhotosModel

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]

    private var extrasSelected: Bool {
        group.extras.allSatisfy { similar.selection.contains($0.id) }
    }

    private var everythingSelected: Bool {
        group.items.allSatisfy { similar.selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.items.count) similar photos")
                        .font(.heading(.headline))
                        .foregroundStyle(Theme.pine)
                    if let date = group.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                Button(extrasSelected ? "Deselect extras" : "Select extras") {
                    Haptics.select()
                    similar.selectExtras(in: group, !extrasSelected)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.pine)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(group.items) { item in
                    let isBest = item.id == group.bestID
                    let isSelected = similar.selection.contains(item.id)
                    SelectableThumbnail(asset: item.asset, isSelected: isSelected, isBest: isBest)
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture {
                            Haptics.select()
                            similar.toggle(item.id)
                        }
                        .contextMenu {
                            if !isBest {
                                Button("Keep this one instead", systemImage: "star") {
                                    Haptics.select()
                                    similar.setBest(item.id, in: group.id)
                                }
                            }
                            Button(isSelected ? "Deselect" : "Select",
                                   systemImage: isSelected ? "circle" : "checkmark.circle") {
                                Haptics.select()
                                similar.toggle(item.id)
                            }
                        } preview: {
                            AssetThumbnail(asset: item.asset, contentMode: .fit)
                                .frame(width: 320, height: 420)
                        }
                }
            }

            if everythingSelected {
                Label("Every photo in this set is selected, so none would be kept.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.coralText)
            }
        }
        .card()
    }
}

/// Progress while photos are compared: a wide bar like the home screen's storage bar.
struct ScanProgressView: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.heroNumber)
                .monospacedDigit()
                .foregroundStyle(Theme.pine)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stone)
                    Capsule()
                        .fill(Theme.pine)
                        .frame(width: max(geometry.size.width * progress, 22))
                }
            }
            .frame(height: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text("Looking for similar photos")
                    .font(.heading(.title3))
                    .foregroundStyle(Theme.pine)
                Text("This happens on your iPhone. You can leave this screen and the scan keeps going.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(Theme.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .combine)
    }
}
