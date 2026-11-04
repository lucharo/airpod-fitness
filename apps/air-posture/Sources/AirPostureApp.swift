import SwiftUI

@main
struct AirPostureApp: App {
    @StateObject private var tracker = PostureTracker()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded && !ProcessInfo.processInfo.arguments.contains("-onboarding") {
                    HomeView(tracker: tracker)
                        .onAppear { tracker.start() }
                } else {
                    OnboardingView(tracker: tracker) { onboarded = true }
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") { onboarded = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            tracker.appStateChanged(isForeground: phase == .active)
        }
    }
}
