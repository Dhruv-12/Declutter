import SwiftUI

@main
struct DeclutterApp: App {
    @State private var model = AppModel()

    init() {
        LaunchTimer.mark(.appInit)
        // Nothing slow here: this runs before the first frame. The font loads on another thread.
        Task.detached(priority: .userInitiated) { FontWarmer.warm() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.pine)
        }
    }
}

/// Shows onboarding the first time, then the dashboard, with the intro on top on a cold launch.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    /// Only true when the app process starts, so returning from the background skips the intro.
    @State private var showIntro = true
    /// The app's screens are added right after the intro's first frame, so that frame has
    /// nothing else to build.
    @State private var showContent = false

    var body: some View {
        ZStack {
            if showContent {
                Group {
                    if hasFinishedOnboarding {
                        DashboardView()
                    } else {
                        OnboardingView { hasFinishedOnboarding = true }
                    }
                }
                // Loads permissions, storage and scans in the background while the intro plays.
                .task { await model.start() }
            }
            if showIntro {
                IntroView(
                    onFirstFrame: {
                        BrandAppearance.apply()
                        showContent = true
                    },
                    onFinished: {
                        showIntro = false
                        // The heavy scans wait until the intro is gone, so they can't slow it down.
                        Task { await model.startScans() }
                    }
                )
                .zIndex(1)
            }
        }
        .statusBarHidden(showIntro)
        .onChange(of: scenePhase) { _, phase in
            // The user may have changed access in the Settings app while we were in the background.
            // At launch `start()` does this, so skip it until then.
            if phase == .active && model.hasStarted {
                model.refreshPermissions()
                model.refreshStorage()
            }
        }
    }
}
