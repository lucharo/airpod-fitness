import SwiftUI

/// Everything adjustable plus the raw numbers, kept off the main screen.
struct SettingsView: View {
    @ObservedObject var tracker: PostureTracker
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Nudge at \(Int(tracker.thresholdDegrees))° below straight ahead",
                            value: $tracker.thresholdDegrees, in: PostureTracker.nudgeRange, step: 1)
                    Stepper("Move reminder after \(Int(tracker.stillReminderMinutes)) min still",
                            value: $tracker.stillReminderMinutes, in: 1...90, step: 1)
                    CalibrateButton(tracker: tracker)
                } footer: {
                    Text("Smaller angles nudge sooner. Recalibrate when you change chair or screen.")
                }

                Section {
                    Toggle("Pause when an AirPod comes out", isOn: $tracker.pauseWhenAirPodOut)
                } footer: {
                    Text("On: take an AirPod out to pause nudges (say, to talk to someone); put it back and they resume. Off: keeps nudging with the AirPod still in, if you wear just one.")
                }

                Section("Known limitations") {
                    limitation("figure.walk", "It measures your head, not your body. Leaning your whole body forward counts as your head dropping, and slouching while your eyes stay level doesn't show.")
                    limitation("airpods", "iOS says which AirPod is measuring, not whether both are in. Pausing only happens when that AirPod comes out (see Measuring from).")
                    limitation("scope", "Taking an AirPod out and back in can change its angle in your ear, so you'll be offered a recalibration. A bud that just shifts in your ear can't be detected; recalibrate if the numbers look off.")
                    limitation("speaker.slash", "Sound only ever plays through headphones. If the AirPods disconnect, nudges pause; they never come out of the phone's speaker.")
                    limitation("mic", "Apps that use the microphone (dictation, calls) can stop the sound. You'll see a banner to turn it back on.")
                }

                Section("AirPods") {
                    row("Motion available", tracker.available ? "Yes" : "No")
                    row("Connected", tracker.connected ? "Yes" : "No")
                    row("Measuring from", tracker.measuringFrom == "left" ? "Left AirPod" : tracker.measuringFrom == "right" ? "Right AirPod" : tracker.measuringFrom)
                    row("AirPod switches", "\(tracker.airPodSwitches)")
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
                    row("Motion restarts (after mic use)", "\(tracker.motionRestarts)")
                    row("Sound", tracker.soundOK ? "On" : "Off (interrupted)")
                    row("Audio interruptions", "\(tracker.audioInterruptions)")
                    Button("Play test chime") { tracker.testChime() }
                    ShareLink("Export log", item: tracker.logURL)
                }

                Section {
                    Button("Show the introduction again") { onboarded = false; dismiss() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func limitation(_ icon: String, _ text: String) -> some View {
        Label { Text(text).font(.subheadline) } icon: { Image(systemName: icon) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value).monospacedDigit()
    }

    private func deg(_ value: Double) -> String { String(format: "%.1f°", value) }
}
