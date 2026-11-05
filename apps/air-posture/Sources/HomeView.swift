import SwiftUI

/// Main screen: a gauge, one status, one button, settings behind a gear.
struct HomeView: View {
    @ObservedObject var tracker: PostureTracker
    @State private var showSettings = false
    @State private var showRecorder = ProcessInfo.processInfo.arguments.contains("-recorder")

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)
                AngleGauge(tracker: tracker)
                CalibrateButton(tracker: tracker)
                    .buttonStyle(.bordered)
                    .tint(.primary)
                Spacer(minLength: 0)
                if tracker.suggestRecalibrate {
                    VStack(spacing: 8) {
                        Label("AirPod back in. Its angle may have changed.", systemImage: "airpods")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            CalibrateButton(tracker: tracker, title: "Recalibrate")
                                .buttonStyle(.borderedProminent).tint(.primary)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                            Button("Not now") { tracker.suggestRecalibrate = false }.buttonStyle(.bordered).tint(.primary)
                        }
                    }
                }
                if tracker.running && !tracker.soundOK && !PostureTracker.isDemo {
                    VStack(spacing: 8) {
                        Label("Sound is off: another app took the audio", systemImage: "speaker.slash")
                            .font(.subheadline.weight(.semibold))
                        Button("Turn sound back on") { tracker.restoreSound() }
                            .buttonStyle(.borderedProminent).tint(.primary)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                }
                if !tracker.connected && tracker.running {
                    Label("AirPods not connected", systemImage: "airpods")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    tracker.running ? tracker.stop() : tracker.start()
                } label: {
                    Label(tracker.running ? "Pause" : "Resume",
                          systemImage: tracker.running ? "pause.fill" : "play.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Air Posture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showRecorder = true } label: { Label("Record", systemImage: "record.circle") }
                        .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(tracker: tracker)
            }
            .fullScreenCover(isPresented: $showRecorder) {
                RecordView(tracker: tracker)
            }
        }
    }
}

/// Shared wording; colour never carries the meaning on its own (icon + words).
struct StatusLine: View {
    @ObservedObject var tracker: PostureTracker
    var body: some View {
        if !tracker.running {
            Label("Paused", systemImage: "pause.circle")
        } else if tracker.pausedForAirPod {
            Label("Paused: an AirPod is out", systemImage: "airpods")
        } else if tracker.isUpright {
            Label("Head level", systemImage: "checkmark.circle.fill")
        } else {
            Label("Head dropping", systemImage: "arrow.down.circle.fill")
        }
    }
}
