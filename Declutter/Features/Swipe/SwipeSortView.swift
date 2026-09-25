import Photos
import SwiftUI

/// A stack of photo cards. Swipe left to mark a photo for deletion, right to keep it.
/// Marked photos go to the review screen; nothing is deleted here.
struct SwipeSortView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero
    @State private var isFlying = false
    @State private var reviewPlan: CleanupPlan?

    private var swipe: SwipeSortModel { model.swipe }
    /// How far a card must travel before letting go decides it.
    private let threshold: CGFloat = 110

    var body: some View {
        content
            .navigationTitle("Swipe to sort")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                if model.photoStatus.canRead && swipe.state == .ready && swipe.deck.count > 0 {
                    SelectionBar(count: swipe.marked.count, bytes: swipe.marked.totalSize, singular: "photo", plural: "photos") {
                        reviewPlan = model.makeSwipePlan()
                    }
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .task { if model.photoStatus.canRead { await swipe.load() } }
    }

    @ViewBuilder private var content: some View {
        if !model.photoStatus.canRead {
            PhotoAccessNeededView()
        } else if swipe.state != .ready {
            LoadingView(text: "Getting your photos…")
        } else if swipe.deck.count == 0 {
            EmptyStateView(
                systemImage: "photo.on.rectangle",
                title: "No photos",
                message: "Photos you take will show up here to sort."
            )
        } else if swipe.deck.isFinished {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "All sorted",
                message: swipe.marked.isEmpty
                    ? "You've been through all \(counted(swipe.deck.count, "photo")) and kept every one."
                    : "You've been through all \(counted(swipe.deck.count, "photo")). Review the ones you marked below.",
                actionTitle: "Start again"
            ) {
                swipe.restart()
            }
        } else {
            deckView
        }
    }

    private var deckView: some View {
        VStack(spacing: Theme.spacing) {
            progress

            ZStack {
                // The next two photos peek out behind the top card.
                ForEach((1...2).reversed(), id: \.self) { depth in
                    if let asset = swipe.asset(at: swipe.deck.position + depth) {
                        PhotoCard(asset: asset)
                            .scaleEffect(1 - CGFloat(depth) * 0.04)
                            .offset(y: CGFloat(depth) * 14)
                            .opacity(depth == 2 ? 0.6 : 1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                if let asset = swipe.current {
                    topCard(asset)
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity)

            controls

            Text("Swipe left to mark for deletion, right to keep.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, Theme.gap)
        }
        .screenBackground()
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(swipe.deck.position + 1) of \(swipe.deck.count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.pine)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stone)
                    Capsule()
                        .fill(Theme.barUsed)
                        .frame(width: geometry.size.width * CGFloat(swipe.deck.position) / CGFloat(max(swipe.deck.count, 1)))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, Theme.page)
        .padding(.top, Theme.gap)
        .accessibilityElement(children: .combine)
    }

    private func topCard(_ asset: PHAsset) -> some View {
        PhotoCard(asset: asset, showsSize: true)
            .overlay(alignment: .topLeading) {
                Stamp(text: "Keep", color: Theme.pineFill, textColor: Theme.onPine)
                    .rotationEffect(.degrees(-12))
                    .padding(22)
                    .opacity(Double(max(drag.width, 0) / threshold))
            }
            .overlay(alignment: .topTrailing) {
                Stamp(text: "Delete", color: Theme.coral, textColor: Theme.onCoral)
                    .rotationEffect(.degrees(12))
                    .padding(22)
                    .opacity(Double(max(-drag.width, 0) / threshold))
            }
            .offset(x: drag.width, y: drag.height * 0.3)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / 22)), anchor: .bottom)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard !isFlying else { return }
                        drag = value.translation
                    }
                    .onEnded { value in
                        let travel = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.25
                        if travel <= -threshold {
                            commit(.delete)
                        } else if travel >= threshold {
                            commit(.keep)
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero }
                        }
                    }
            )
            .id(asset.localIdentifier)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photoLabel(asset))
            .accessibilityHint("Swipe left to mark for deletion, right to keep")
            .accessibilityAction(named: "Keep") { commit(.keep) }
            .accessibilityAction(named: "Mark for deletion") { commit(.delete) }
            .accessibilityIdentifier("swipe.card")
    }

    private var controls: some View {
        HStack(spacing: 28) {
            RoundButton(systemImage: "xmark", label: "Mark for deletion", size: 64, fill: Theme.coral, foreground: Theme.onCoral) {
                commit(.delete)
            }
            .accessibilityIdentifier("swipe.delete")
            RoundButton(systemImage: "arrow.uturn.backward", label: "Undo", size: 48, fill: Theme.stone, foreground: Theme.pine) {
                Haptics.select()
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { swipe.undo() }
            }
            .disabled(!swipe.deck.canUndo || isFlying)
            .opacity(swipe.deck.canUndo ? 1 : 0.4)
            .accessibilityIdentifier("swipe.undo")
            RoundButton(systemImage: "checkmark", label: "Keep", size: 64, fill: Theme.pineFill, foreground: Theme.onPine) {
                commit(.keep)
            }
            .accessibilityIdentifier("swipe.keep")
        }
        .disabled(isFlying)
    }

    /// Sends the top card off screen, then records the decision.
    private func commit(_ decision: SwipeDeck.Decision) {
        guard !isFlying, swipe.current != nil else { return }
        Haptics.select()
        if reduceMotion {
            swipe.decide(decision)
            drag = .zero
            return
        }
        isFlying = true
        let direction: CGFloat = decision == .delete ? -1 : 1
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: direction * 600, height: drag.height)
        } completion: {
            swipe.decide(decision)
            drag = .zero
            isFlying = false
        }
    }

    private func photoLabel(_ asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "Photo" }
        return "Photo from \(date.formatted(date: .long, time: .shortened))"
    }
}

/// One photo on a card, with its date (and size on the top card) along the bottom.
private struct PhotoCard: View {
    let asset: PHAsset
    var showsSize = false
    @State private var size: Int64?

    var body: some View {
        AssetThumbnail(asset: asset)
            .overlay(alignment: .bottom) {
                HStack {
                    if let date = asset.creationDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Spacer()
                    if let size {
                        Text(ByteFormat.string(size))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(Theme.spacing)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(.rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Theme.cardBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            .task(id: asset.localIdentifier) {
                guard showsSize else { return }
                size = await Task.detached(priority: .utility) { SizeCache.shared.size(of: asset) }.value
            }
    }
}

private struct Stamp: View {
    let text: String
    let color: Color
    let textColor: Color

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .rounded, weight: .heavy))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(color, in: .capsule)
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: String
    let size: CGFloat
    let fill: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(fill, in: .circle)
                .overlay { Circle().strokeBorder(Theme.cardBorder, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
