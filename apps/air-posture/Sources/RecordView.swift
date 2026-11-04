import SwiftUI

/// Full-screen guided recording. Instructions are spoken, so you don't need to look at the phone
/// (except in the "look at your phone" position).
struct RecordView: View {
    @ObservedObject var tracker: PostureTracker
    @StateObject private var recorder = PositionRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if recorder.isRecording, let step = recorder.current {
                    recording(step)
                } else if recorder.finished {
                    finished
                } else {
                    intro
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Record positions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if recorder.isRecording {
                    Button("Stop", role: .destructive) { recorder.cancel() }
                } else {
                    Button("Close") { dismiss() }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording)
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-autoRecord") { recorder.start(tracker: tracker) }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("About \(Int((recorder.totalDuration / 60).rounded())) minutes, spoken instructions")
                .font(.title2.bold())
            Text("Keep your AirPods in and put the phone face up on the desk. For each position you'll hear: sit upright, go fully into the position, hold, back to upright, twice. Turn the volume up.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(PositionRecorder.positions) { p in
                    Label(p.title, systemImage: "circle").font(.subheadline)
                }
            }
            Spacer()
            if !tracker.connected && !PostureTracker.isDemo {
                Label("Connect your AirPods first", systemImage: "airpods").foregroundStyle(.secondary)
            }
            Button {
                recorder.start(tracker: tracker)
            } label: {
                Text("Start recording").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .disabled(!tracker.connected && !PostureTracker.isDemo)
        }
    }

    private func recording(_ step: PositionRecorder.Step) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressView(value: recorder.elapsedFraction)
            Text(step.position.map { "\($0.title) · \(step.rep) of \(PositionRecorder.reps)" } ?? "Baseline")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(headline(step)).font(.system(size: 40, weight: .bold))
            Text("\(recorder.secondsLeftInStep)")
                .font(.system(size: 96, weight: .semibold, design: .rounded)).monospacedDigit()
            Spacer()
            Label("\(recorder.sampleCount) samples", systemImage: "waveform.path.ecg")
                .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            if step.position != nil {
                Button("Skip this position") { recorder.skipPosition() }
                    .buttonStyle(.bordered).tint(.primary)
            }
        }
    }

    private func headline(_ step: PositionRecorder.Step) -> String {
        switch step.phase {
        case "into": step.position?.cue ?? ""
        case "hold": "Hold"
        case "back": "Back to upright"
        default: "Sit upright"
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Recording saved", systemImage: "checkmark.circle.fill").font(.title.bold())
            Text("\(recorder.sampleCount) samples. Send the file to your Mac with AirDrop (it lands in Downloads), or save it to Files.")
                .foregroundStyle(.secondary)
            Spacer()
            if let url = recorder.fileURL {
                ShareLink(item: url) {
                    Label("Export recording", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
            }
            Button("Record again") { recorder.start(tracker: tracker) }
                .buttonStyle(.bordered).tint(.primary)
        }
    }
}
