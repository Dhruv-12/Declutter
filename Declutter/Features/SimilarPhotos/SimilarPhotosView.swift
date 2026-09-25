import Photos
import SwiftUI

/// Groups of similar photos. The best shot in each group is kept; the rest are pre-selected.
struct SimilarPhotosView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?

    private var similar: SimilarPhotosModel { model.similar }

    var body: some View {
        content
            .navigationTitle("Similar Photos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .safeAreaInset(edge: .bottom) {
                if !similar.selection.isEmpty {
                    SelectionBar(count: similar.selection.count, bytes: similar.selectedItems.totalSize, actionTitle: "Review") {
                        reviewPlan = model.makePlan(for: [.similarPhotos])
                    }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: similar.selection.isEmpty)
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
                ContentUnavailableView {
                    Label("Find Similar Photos", systemImage: "square.on.square")
                } actions: {
                    Button("Scan Now") { similar.scan() }
                        .buttonStyle(.borderedProminent)
                }
            case .scanning(let progress):
                ScanProgressView(progress: progress)
            case .done:
                if similar.groups.isEmpty {
                    ContentUnavailableView(
                        "No Similar Photos",
                        systemImage: "checkmark.seal",
                        description: Text("Checked \(similar.scannedCount) photos. Nothing looks alike.")
                    )
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

            VStack(alignment: .leading, spacing: 4) {
                Text("\(similar.groups.count) groups · \(similar.extras.count) extra photos · \(ByteFormat.string(similar.extras.totalSize))")
                    .font(.subheadline.weight(.medium))
                if let duration = similar.scanDuration {
                    Text("Checked \(similar.scannedCount) photos in \(duration, format: .number.precision(.fractionLength(1))) s, on this iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

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
            .padding(.top, 8)

            LazyVStack(spacing: 16) {
                ForEach(similar.groups) { group in
                    SimilarGroupCard(group: group, similar: similar)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var optionsMenu: some View {
        Menu {
            Button("Scan Again", systemImage: "arrow.clockwise") { similar.scan() }
            Picker(selection: Binding(get: { similar.strictness }, set: { similar.strictness = $0 })) {
                ForEach(MatchStrictness.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Match", systemImage: "slider.horizontal.3")
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

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 6)]

    private var extrasSelected: Bool {
        group.extras.allSatisfy { similar.selection.contains($0.id) }
    }

    private var everythingSelected: Bool {
        group.items.allSatisfy { similar.selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.items.count) similar photos")
                        .font(.headline)
                    if let date = group.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(extrasSelected ? "Deselect" : "Select Extras") {
                    similar.selectExtras(in: group, !extrasSelected)
                }
                .font(.subheadline)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(group.items) { item in
                    let isBest = item.id == group.bestID
                    let isSelected = similar.selection.contains(item.id)
                    SelectableThumbnail(asset: item.asset, isSelected: isSelected, badge: isBest ? "★ Best" : nil)
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture { similar.toggle(item.id) }
                        .contextMenu {
                            if !isBest {
                                Button("Keep This One Instead", systemImage: "star") {
                                    similar.setBest(item.id, in: group.id)
                                }
                            }
                            Button(isSelected ? "Deselect" : "Select",
                                   systemImage: isSelected ? "circle" : "checkmark.circle") {
                                similar.toggle(item.id)
                            }
                        } preview: {
                            AssetThumbnail(asset: item.asset, contentMode: .fit)
                                .frame(width: 320, height: 420)
                        }
                }
            }

            if everythingSelected {
                Label("Every photo in this group is selected. None would be kept.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

struct ScanProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.15), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.title.bold().monospacedDigit())
            }
            .frame(width: 140, height: 140)

            VStack(spacing: 6) {
                Text("Looking for similar photos…")
                    .font(.headline)
                Text("This happens on your iPhone. You can leave this screen and the scan keeps going.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
