import SwiftUI

@main
struct DeclutterApp: App {
    @State private var model = AppModel()

    init() {
        LaunchTimer.mark("App init started")
        BrandAppearance.apply()
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

    var body: some View {
        ZStack {
            Group {
                if hasFinishedOnboarding {
                    DashboardView()
                } else {
                    OnboardingView { hasFinishedOnboarding = true }
                }
            }
            if showIntro {
                IntroView { showIntro = false }
                    .zIndex(1)
            }
        }
        .statusBarHidden(showIntro)
        // Starts straight away, behind the intro, so nobody waits for it.
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            // The user may have changed access in the Settings app while we were in the background.
            if phase == .active {
                model.refreshPermissions()
                model.refreshStorage()
            }
        }
    }
}
