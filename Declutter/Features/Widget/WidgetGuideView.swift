import SwiftUI
import WidgetKit

/// What the Home Screen widget looks like, with the steps to add it.
struct WidgetGuideView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing * 1.5) {
                ScreenSummary(
                    text: "See your free space at a glance",
                    detail: "The widget works out your storage on this iPhone and updates on its own. Tap it to open Declutter."
                )
                .padding(.horizontal, -Theme.page)

                HStack(alignment: .top, spacing: Theme.spacing) {
                    preview(.systemSmall, width: 158)
                    Spacer(minLength: 0)
                }
                preview(.systemMedium, width: nil)

                VStack(alignment: .leading, spacing: Theme.gap + 4) {
                    Text("Add the widget")
                        .font(.heading(.title3))
                        .foregroundStyle(Theme.pine)
                        .accessibilityIdentifier("widget.steps")
                    Step(number: 1, text: "Touch and hold an empty spot on your Home Screen until the apps jiggle.")
                    Step(number: 2, text: "Tap Edit in the top corner, then Add Widget.")
                    Step(number: 3, text: "Search for Declutter, pick the small or medium size, and tap Add Widget.")
                }
                .card()
            }
            .padding(.horizontal, Theme.page)
            .padding(.vertical, Theme.spacing)
        }
        .screenBackground()
        .navigationTitle("Home Screen widget")
        .navigationBarTitleDisplayMode(.large)
    }

    /// The real widget view, drawn at widget size on a Home Screen-like card.
    private func preview(_ family: WidgetFamily, width: CGFloat?) -> some View {
        StorageWidgetView(storage: model.storage, family: family)
            .padding(16)
            .frame(width: width, height: 158)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(BrandColors.mist, in: .rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.hairline, lineWidth: 1) }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            .accessibilityLabel("Preview of the \(family == .systemMedium ? "medium" : "small") widget")
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.onPine)
                .frame(width: 26, height: 26)
                .background(Theme.pineFill, in: .circle)
            Text(text)
                .foregroundStyle(Theme.pine)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
