import SwiftUI

/// Record positions. The screen is only for setup and results: once started, the phone goes down
/// on the desk (or into a chest pocket) and everything is spoken. The ring and dot are there for a glance,
/// never needed to follow along.
struct RecordView: View {
    @ObservedObject var tracker: PostureTracker
    @StateObject private var recorder = PositionRecorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch recorder.stage {
                case .intro: intro
                case .done: finished
                default: recording
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Record positions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if recorder.isRecording {
                    Button("Stop") { recorder.stop() }
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

    // MARK: intro (the only part you read)

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Show the app how you sit").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                step("1", "Tap Start, then put the phone \(recorder.pocketMode ? "in your chest pocket" : "down on the desk"). You won't need to look at it again.")
                step("2", "A voice tells you each position. Move into it and hold still until the chime.")
                step("3", "Come back to how you usually sit. The next one follows by itself.")
            }
            Text("\(PositionRecorder.positions.count) positions, twice each, about 3 minutes. Volume up.")
                .font(.subheadline).foregroundStyle(.secondary)
            Toggle(isOn: $recorder.pocketMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone in a chest pocket")
                    Text("Also records your back, so slouching shows up.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !tracker.connected && !PostureTracker.isDemo {
                Label("Put both AirPods in first", systemImage: "airpods").foregroundStyle(.secondary)
            }
            Button {
                recorder.start(tracker: tracker)
            } label: {
                Text("Start").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .disabled(!tracker.connected && !PostureTracker.isDemo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(n).font(.headline.monospacedDigit()).frame(width: 18)
            Text(text)
        }
    }

    // MARK: recording (glanceable only)

    private var recording: some View {
        VStack(spacing: 28) {
            Text(headline)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .frame(minHeight: 90)
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 14)
                Circle().trim(from: 0, to: recorder.fill)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.15), value: recorder.fill)
                if recorder.hasCentre {
                    pointer
                } else {
                    Image(systemName: recorder.stage == .placing ? "iphone.and.arrow.forward" : "display")
                        .font(.system(size: 52)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 220, height: 220)
            Text(hint).font(.headline).foregroundStyle(.secondary).frame(minHeight: 24)
            Spacer()
            if !tracker.connected && !PostureTracker.isDemo {
                Label("An AirPod is out. Put it back in to continue", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
            HStack {
                Text("\(recorder.completed)/\(recorder.total) done")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if recorder.hasCentre, recorder.position != nil {
                    Button("Skip") { recorder.skipPosition() }.buttonStyle(.bordered).tint(.primary)
                }
            }
        }
    }

    /// A dot that follows your head relative to how you usually sit (shown only once that is captured).
    private var pointer: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 10, height: 10)
            let scale = 2.0, limit = 85.0
            Circle().fill(Color.primary).frame(width: 24, height: 24)
                .offset(x: max(-limit, min(limit, -recorder.offsetYaw * scale)),
                        y: max(-limit, min(limit, -recorder.offsetPitch * scale)))
                .animation(.easeOut(duration: 0.12), value: recorder.offsetPitch)
        }
    }

    private var headline: String {
        switch recorder.stage {
        case .placing: recorder.pocketMode ? "Phone in your chest pocket" : "Put the phone down"
        case .usual: "Sit as you usually do, looking straight ahead"
        case .into, .hold: recorder.position?.title ?? ""
        case .back: "Come back"
        case .rest: "Next: \(nextTitle)"
        default: ""
        }
    }

    private var nextTitle: String {
        if recorder.rep < PositionRecorder.reps { return recorder.position?.title ?? "" }
        let i = recorder.index + 1
        return PositionRecorder.positions.indices.contains(i) ? PositionRecorder.positions[i].title : "done"
    }

    private var hint: String {
        switch recorder.stage {
        case .placing: "Starts when the phone is still"
        case .usual, .hold, .rest: recorder.fill > 0 ? "Hold still…" : "Keep still"
        case .into: "Move into it, then hold still"
        case .back: "Then hold still"
        default: ""
        }
    }

    // MARK: finished

    private var finished: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recording saved", systemImage: "checkmark.circle.fill").font(.largeTitle.bold())
            Text("\(recorder.completed) of \(recorder.total) done, \(recorder.sampleCount) samples. Export it and AirDrop it to your Mac.")
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
