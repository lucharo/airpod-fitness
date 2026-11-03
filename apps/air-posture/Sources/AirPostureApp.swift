import SwiftUI

@main
struct AirPostureApp: App {
    @StateObject private var tracker = PostureTracker()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(tracker: tracker)
        }
        .onChange(of: scenePhase) { _, phase in
            tracker.appStateChanged(isForeground: phase == .active)
        }
    }
}
