import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    StorageCard(storage: model.storage, reclaimable: model.reclaimableBytes)

                    PermissionBanners()

                    Text("Clean Up")
                        .font(.title3.bold())
                        .padding(.top, 4)

                    VStack(spacing: 12) {
                        ForEach(CleanupCategory.allCases) { category in
                            NavigationLink(value: category) {
                                CategoryCard(category: category, summary: model.summary(for: category))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Label("Scanning happens on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Declutter")
            .navigationDestination(for: CleanupCategory.self) { category in
                destination(for: category)
            }
            .refreshable {
                model.refreshPermissions()
                await model.reloadLibrary()
            }
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

struct StorageCard: View {
    let storage: DeviceStorage?
    let reclaimable: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                StorageRing(fraction: storage?.usedFraction ?? 0)
                    .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 6) {
                    Text("iPhone Storage")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let storage {
                        Text(ByteFormat.string(storage.used))
                            .font(.title.bold())
                            .contentTransition(.numericText())
                        Text("used of \(ByteFormat.string(storage.total))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(ByteFormat.string(storage.available)) free")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Text("Unavailable").font(.title3.bold())
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            HStack {
                Label("Can be freed", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(ByteFormat.string(reclaimable))
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .contentTransition(.numericText())
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .animation(.default, value: reclaimable)
    }
}

struct StorageRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.title2.bold())
                Text("used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct CategoryCard: View {
    let category: CleanupCategory
    let summary: CategorySummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.systemImage)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(category.tint.gradient, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(category.tint)
        case .needsAccess:
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}
