import Photos
import SwiftUI

/// Blurry photos, blurriest first, with multi-select. Deleting goes through the review screen.
struct BlurryPhotosView: View {
    @Environment(AppModel.self) private var model
    @State private var reviewPlan: CleanupPlan?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.gridGap), count: 3)

    private var blurry: BlurryPhotosModel { model.blurry }

    var body: some View {
        content
            .navigationTitle("Blurry photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { optionsMenu }
            }
            .safeAreaInset(edge: .bottom) {
                if model.photoStatus.canRead && blurry.state == .done && !blurry.photos.isEmpty {
                    SelectionBar(count: blurry.selection.count, bytes: blurry.selectedItems.totalSize, singular: "photo", plural: "photos") {
                        reviewPlan = model.makeBlurryPlan()
                    }
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .onAppear {
                if blurry.state == .idle && model.photoStatus.canRead { blurry.scan() }
            }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else {
            switch blurry.state {
            case .idle:
                EmptyStateView(
                    systemImage: Tool.blurry.systemImage,
                    title: "Find blurry photos",
                    message: "Declutter checks each photo's sharpness on this iPhone and lists the blurriest first.",
                    actionTitle: "Scan photos"
                ) {
                    blurry.scan()
                }
            case .scanning(let progress):
                ScanProgressView(
                    progress: progress,
                    title: "Looking for blurry photos",
                    message: "This happens on your iPhone. You can leave this screen and the scan keeps going."
                )
            case .done:
                if blurry.photos.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.seal",
                        title: "No blurry photos",
                        message: blurry.level == .soft
                            ? "Checked \(counted(blurry.scannedCount, "photo")). Everything looks sharp."
                            : "Checked \(counted(blurry.scannedCount, "photo")). To see softer photos too, choose Include slightly soft.",
                        actionTitle: blurry.level == .soft ? nil : "Include slightly soft"
                    ) {
                        blurry.level = .soft
                    }
                } else {
                    grid
                }
            }
        }
    }

    private var grid: some View {
        let photos = blurry.photos
        let items = photos.map(\.item)
        return ScrollView {
            ScreenSummary(
                text: "\(counted(photos.count, "blurry photo")) · \(ByteFormat.string(items.totalSize))",
                detail: "Blurriest first. Checked \(counted(blurry.scannedCount, "photo")). Long-press to look closer."
            )
            .padding(.top, Theme.gap)

            BulkActionBar {
                let allSelected = items.allSatisfy { blurry.selection.contains($0.id) }
                BulkActionButton(
                    title: allSelected ? "Deselect all" : "Select all",
                    count: items.count,
                    bytes: items.totalSize,
                    systemImage: allSelected ? "circle" : "checkmark.circle"
                ) {
                    if allSelected {
                        blurry.selection.subtract(items.map(\.id))
                    } else {
                        blurry.selection.formUnion(items.map(\.id))
                    }
                }
            }
            .padding(.vertical, Theme.gap)

            LazyVGrid(columns: columns, spacing: Theme.gridGap) {
                ForEach(photos) { photo in
                    let isSelected = blurry.selection.contains(photo.id)
                    SelectableThumbnail(asset: photo.item.asset, isSelected: isSelected)
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture {
                            Haptics.select()
                            blurry.toggle(photo.id)
                        }
                        .contextMenu {
                            Button(isSelected ? "Deselect" : "Select",
                                   systemImage: isSelected ? "circle" : "checkmark.circle") {
                                Haptics.select()
                                blurry.toggle(photo.id)
                            }
                        } preview: {
                            AssetThumbnail(asset: photo.item.asset, contentMode: .fit)
                                .frame(width: 320, height: 420)
                        }
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, Theme.spacing)
        }
        .screenBackground()
    }

    private var optionsMenu: some View {
        Menu {
            Button("Scan again", systemImage: "arrow.clockwise") { blurry.scan() }
            Picker(selection: Binding(get: { blurry.level }, set: { blurry.level = $0 })) {
                ForEach(BlurLevel.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("How blurry", systemImage: "slider.horizontal.3")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
        .disabled(!model.photoStatus.canRead)
    }
}
