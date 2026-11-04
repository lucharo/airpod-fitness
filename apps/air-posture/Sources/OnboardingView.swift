import SwiftUI

/// First launch: what the app does, AirPods in, sit tall and calibrate. Three steps, one button each.
struct OnboardingView: View {
    @ObservedObject var tracker: PostureTracker
    var finish: () -> Void
    @State private var step = Self.initialStep

    private static var initialStep: Int {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-onboardingStep").flatMap { Int(args[$0 + 1]) } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Capsule().fill(i <= step ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Spacer()
            Group {
                switch step {
                case 0: intro
                case 1: airpods
                default: calibrate
                }
            }
            .padding(.horizontal, 28)
            Spacer()

            Button(action: next) {
                Text(buttonTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .disabled(step == 1 && !tracker.connected && !PostureTracker.isDemo)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("AppIconImage").resizable().frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Keep your head up while you sit.").font(.largeTitle.bold())
            Text("Air Posture reads the motion sensors in your AirPods. When your head drops forward past your upright position, you hear a soft tone that gets stronger the further you go. Sit back up and it stops.")
                .font(.body).foregroundStyle(.secondary)
        }
    }

    private var airpods: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: tracker.connected ? "checkmark.circle.fill" : "airpods")
                .font(.system(size: 56, weight: .regular))
            Text(tracker.connected ? "AirPods connected" : "Put your AirPods in").font(.largeTitle.bold())
            Text("Works with AirPods Pro, AirPods 3 and 4, AirPods Max and Beats Fit Pro. iOS will ask for Motion permission; that is only for head movement.")
                .foregroundStyle(.secondary)
        }
        .onAppear { tracker.start() }
    }

    private var calibrate: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "level")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("Sit tall, look at your screen").font(.largeTitle.bold())
            Text("Shoulders back, eyes level with the screen. Tap the button while holding that position; it becomes your upright reference. You can recalibrate any time.")
                .foregroundStyle(.secondary)
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0: "Get started"
        case 1: tracker.connected || PostureTracker.isDemo ? "Continue" : "Waiting for AirPods…"
        default: "This is my upright position"
        }
    }

    private func next() {
        if step < 2 { withAnimation { step += 1 }; return }
        tracker.calibrate()
        finish()
    }
}
