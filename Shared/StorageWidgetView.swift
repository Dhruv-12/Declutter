import SwiftUI
import WidgetKit

/// The words and numbers the storage widget shows. Pure logic, unit tested.
nonisolated struct StorageSummary: Equatable {
    let free: String
    let used: String
    let total: String
    /// 0...1, how full the storage is.
    let usedFraction: Double

    init(_ storage: DeviceStorage) {
        free = ByteFormat.string(storage.available)
        used = ByteFormat.string(storage.used)
        total = ByteFormat.string(storage.total)
        usedFraction = min(max(storage.usedFraction, 0), 1)
    }

    var accessibilityLabel: String { "\(free) free of \(total). \(used) used." }
}

/// The Home Screen widget in the Declutter style: free space, a storage bar and used space.
/// Shared with the app so its widget tile can show exactly what the widget looks like.
struct StorageWidgetView: View {
    let storage: DeviceStorage?
    let family: WidgetFamily

    var body: some View {
        Group {
            if let storage {
                let summary = StorageSummary(storage)
                if family == .systemMedium {
                    medium(summary)
                } else {
                    small(summary)
                }
            } else {
                unavailable
            }
        }
        .containerBackground(for: .widget) { BrandColors.mist }
    }

    private var brand: some View {
        Label("Declutter", systemImage: "internaldrive")
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(BrandColors.secondaryText)
    }

    private func small(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            brand
            Spacer(minLength: 0)
            freeSpace(summary, size: 30)
            WidgetStorageBar(fraction: summary.usedFraction)
                .frame(height: 10)
            Text("\(summary.used) used")
                .font(.caption2.weight(.medium))
                .foregroundStyle(BrandColors.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private func medium(_ summary: StorageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            brand
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                freeSpace(summary, size: 36)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    legend(color: BrandColors.barUsed, title: "Used", value: summary.used)
                    legend(color: BrandColors.barTrack, title: "Free", value: summary.free, outlined: true)
                }
            }
            WidgetStorageBar(fraction: summary.usedFraction)
                .frame(height: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private func freeSpace(_ summary: StorageSummary, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.free)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColors.pine)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .widgetAccentable()
            Text("free of \(summary.total)")
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandColors.secondaryText)
        }
    }

    private func legend(color: Color, title: String, value: String, outlined: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .overlay { if outlined { Circle().strokeBorder(BrandColors.secondaryText.opacity(0.4), lineWidth: 1) } }
                .frame(width: 8, height: 8)
            Text(title).foregroundStyle(BrandColors.secondaryText)
            Text(value).fontWeight(.semibold).foregroundStyle(BrandColors.pine)
        }
        .font(.caption)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            brand
            Spacer(minLength: 0)
            Text("Open Declutter to see your storage")
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandColors.pine)
        }
    }
}

/// Used space as a smooth rounded bar on the Stone track, like the app's home screen.
struct WidgetStorageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(BrandColors.barTrack)
                Capsule()
                    .fill(BrandColors.barUsed)
                    .frame(width: max(geometry.size.width * fraction, geometry.size.height))
                    .widgetAccentable()
            }
        }
        .overlay { Capsule().strokeBorder(BrandColors.cardBorder, lineWidth: 1) }
    }
}
