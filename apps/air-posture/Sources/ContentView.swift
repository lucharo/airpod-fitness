import SwiftUI

struct ContentView: View {
    @ObservedObject var tracker: PostureTracker

    var body: some View {
        NavigationStack {
            Form {
                Section("AirPods") {
                    row("Motion available", tracker.available ? "yes" : "no")
                    row("Connected", tracker.connected ? "yes" : "no")
                    if let error = tracker.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section("Head") {
                    row("Pitch", deg(tracker.pitch))
                    row("Roll", deg(tracker.roll))
                    row("Yaw", deg(tracker.yaw))
                    row("Baseline", tracker.baselinePitch.map(deg) ?? "not set")
                    row("Drop past baseline", deg(tracker.drop))
                        .foregroundStyle(tracker.drop > tracker.thresholdDegrees ? .red : .primary)
                    Button("Sit tall, then calibrate") { tracker.calibrate() }
                        .disabled(!tracker.running)
                }
                Section("Feedback") {
                    Stepper("Tone starts at \(Int(tracker.thresholdDegrees))°",
                            value: $tracker.thresholdDegrees, in: 4...40, step: 2)
                    Stepper("Move reminder after \(Int(tracker.stillReminderMinutes)) min",
                            value: $tracker.stillReminderMinutes, in: 1...90, step: 1)
                    row("Still for", "\(Int(tracker.secondsStill)) s")
                }
                Section("Background test") {
                    row("Samples", "\(tracker.sampleCount)")
                    row("Samples in background", "\(tracker.backgroundSamples)")
                    row("Longest gap in background", String(format: "%.1f s", tracker.longestBackgroundGap))
                    ShareLink("Export log", item: tracker.logURL)
                }
                Section {
                    Button(tracker.running ? "Stop" : "Start") {
                        tracker.running ? tracker.stop() : tracker.start()
                    }
                }
            }
            .navigationTitle("Air Posture")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value).monospacedDigit()
    }

    private func deg(_ value: Double) -> String { String(format: "%.1f°", value) }
}
