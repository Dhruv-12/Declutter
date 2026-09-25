import SwiftUI

/// The intro on a cold launch (about 1.2 seconds from its first frame): scattered letters spring
/// into the word "Declutter", a Mint bar slides in underneath, then everything fades into the app.
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
                                    ? .easeOut(duration: 0.3)
                                    : .spring(response: 0.45, dampingFraction: 0.72).delay(Double(index) * 0.025),
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
            LaunchTimer.mark("Intro view appeared")
            Haptics.prepareLight()
            // Start on the first screen refresh: the scattered frame is on screen, nothing waits.
            firstFrame.wait {
                LaunchTimer.mark("First intro frame on screen")
                onFirstFrame()
                play()
            }
        }
    }

    /// Letters settle (~0.6 s), the bar slides in (~0.25 s), then a 0.3 s fade: about 1.15 s in all.
    private func play() {
        LaunchTimer.mark("Intro animation started")
        settled = true
        Task {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { barShown = true }
                try? await Task.sleep(for: .milliseconds(500))
            } else {
                try? await Task.sleep(for: .milliseconds(600))
                Haptics.light()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { barShown = true }
                try? await Task.sleep(for: .milliseconds(250))
            }
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: 0.3)) { fadingOut = true }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            LaunchTimer.mark("Intro finished")
            onFinished()
        }
    }
}
