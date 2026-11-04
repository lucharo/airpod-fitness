import SwiftUI

/// Everything adjustable plus the raw numbers, kept off the main screen.
struct SettingsView: View {
    @ObservedObject var tracker: PostureTracker
    @Binding var variant: String
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Nudge after \(Int(tracker.thresholdDegrees))° of head drop",
                            value: $tracker.thresholdDegrees, in: 4...40, step: 2)
                    Stepper("Move reminder after \(Int(tracker.stillReminderMinutes)) min still",
                            value: $tracker.stillReminderMinutes, in: 1...90, step: 1)
                    Button("Recalibrate (sit tall first)") { tracker.calibrate() }
                        .disabled(!tracker.running)
                } footer: {
                    Text("Smaller angles nudge sooner. Recalibrate when you change chair or screen.")
                }

                Section("AirPods") {
                    row("Motion available", tracker.available ? "Yes" : "No")
                    row("Connected", tracker.connected ? "Yes" : "No")
                    if let error = tracker.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Diagnostics") {
                    row("Pitch", deg(tracker.pitch))
                    row("Roll", deg(tracker.roll))
                    row("Yaw", deg(tracker.yaw))
                    row("Baseline", tracker.baselinePitch.map(deg) ?? "not set")
                    row("Samples", "\(tracker.sampleCount)")
                    row("Samples in background", "\(tracker.backgroundSamples)")
                    row("Longest gap in background", String(format: "%.1f s", tracker.longestBackgroundGap))
                    ShareLink("Export log", item: tracker.logURL)
                }

                Section {
                    Picker("Main screen layout", selection: $variant) {
                        Text("A gauge").tag("A")
                        Text("B words").tag("B")
                        Text("C plumb").tag("C")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Prototype")
                } footer: {
                    Text("Try each layout and tell me which letter reads best.")
                }

                Section {
                    Button("Show the introduction again") { onboarded = false; dismiss() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value).monospacedDigit()
    }

    private func deg(_ value: Double) -> String { String(format: "%.1f°", value) }
}
