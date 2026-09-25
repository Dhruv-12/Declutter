import SwiftUI

@main
struct DeclutterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// Shows onboarding the first time, then the dashboard.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    var body: some View {
        Group {
            if hasFinishedOnboarding {
                DashboardView()
            } else {
                OnboardingView { hasFinishedOnboarding = true }
            }
        }
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
