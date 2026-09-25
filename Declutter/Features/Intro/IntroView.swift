import SwiftUI

/// The intro on a cold launch, capped at 1.2 seconds from its first frame: scattered letters spring
/// into the word "Declutter", a Mint bar slides in underneath, then everything fades into the app.
///
/// Fixed timeline, every step measured from when the animation starts:
///   0.00 s  letters spring into place (short spring, 0.03 s apart; they aren't waited on)
///   0.60 s  light haptic, Mint bar slides in
///   1.00 s  fade to home starts
///   1.20 s  intro gone
///
/// It starts on the very first screen refresh and never waits for data: the app loads behind it.
/// Tapping skips it. With Reduce Motion on, the word simply fades in and out.
struct IntroView: View {
    /// Called once the intro's first frame is on screen, so the app can start building behind it.
    var onFirstFrame: () -> Void = {}
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var barShown = false
    @State private var fadingOut = false
    @State private var finished = false
    @State private var firstFrame = FirstFrameSignal()

    private let letters = Array("Declutter")

    /// Where each letter starts, as clutter around the centre. Fixed so every launch looks the same.
    private let scatter: [(x: CGFloat, y: CGFloat, angle: Double)] = [
        (-60, -110, -38), (35, 120, 52), (-95, 45, 24), (80, -135, -61), (-25, 150, 80),
        (105, 70, -30), (-80, -55, 70), (50, -85, 35), (115, 125, -55),
    ]

    var body: some View {
        ZStack {
            Theme.Brand.pine.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                        Text(String(letter))
                            .offset(settled || reduceMotion ? .zero : CGSize(width: scatter[index].x, height: scatter[index].y))
                            .rotationEffect(.degrees(settled || reduceMotion ? 0 : scatter[index].angle))
                            .scaleEffect(settled || reduceMotion ? 1 : 0.85)
                            .opacity(settled ? 1 : (reduceMotion ? 0 : 0.35))
                            .animation(
                                reduceMotion
                                    ? .easeOut(duration: 0.25)
                                    : .spring(response: 0.35, dampingFraction: 0.8).delay(Double(index) * 0.03),
                                value: settled
                            )
                    }
                }
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Brand.mist)

                Capsule()
                    .fill(Theme.Brand.mint)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .offset(x: barShown || reduceMotion ? 0 : -320)
                    .opacity(barShown ? 1 : 0)
            }
            .fixedSize()
        }
        .opacity(fadingOut ? 0 : 1)
        .contentShape(.rect)
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel("Declutter")
        .accessibilityAddTraits(.isHeader)
        .onAppear {
            // Start on the first screen refresh: the scattered frame is on screen, nothing waits.
            firstFrame.wait {
                LaunchTimer.mark(.firstFrame)
                play()
                // Waking the Taptic Engine is slow, so it happens after the first frame;
                // the haptic isn't needed until 0.6 s.
                Haptics.prepareLight()
                onFirstFrame()
            }
        }
    }

    private func play() {
        LaunchTimer.mark(.animationStart)
        let start = ContinuousClock.now
        settled = true
        Task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.25)) { barShown = true }
            } else {
                try? await Task.sleep(until: start + .milliseconds(600), clock: .continuous)
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { barShown = true }
            }
            try? await Task.sleep(until: start + .milliseconds(1000), clock: .continuous)
            finish()
        }
    }

    /// Fades into the app. Also used when the intro is tapped to skip it.
    private func finish() {
        guard !finished else { return }
        finished = true
        let start = ContinuousClock.now
        withAnimation(.easeOut(duration: 0.2)) { fadingOut = true }
        Task {
            try? await Task.sleep(until: start + .milliseconds(200), clock: .continuous)
            LaunchTimer.mark(.animationEnd)
            onFinished()
        }
    }
}
