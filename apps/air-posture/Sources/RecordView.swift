import SwiftUI

/// Guided, motion-driven recording, in the spirit of Face ID enrolment: a dot follows your head,
/// the ring fills while you hold still, a tick and chime say come back. No timer.
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

    // MARK: intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Show the app how you sit").font(.largeTitle.bold())
            Text("You'll move into \(recorder.active.count) positions, twice each. Hold still while the ring fills, then come back. It moves on by itself; about 3 minutes.")
                .foregroundStyle(.secondary)
            Toggle(isOn: $recorder.pocketMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iPhone in a chest pocket")
                    Text("Also records your trunk, to catch slouching. Position names are read aloud.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !tracker.connected && !PostureTracker.isDemo {
                Label("Put both AirPods in first", systemImage: "airpods").foregroundStyle(.secondary)
            }
            primaryButton("Start") { recorder.start(tracker: tracker) }
                .disabled(!tracker.connected && !PostureTracker.isDemo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: recording

    private var recording: some View {
        VStack(spacing: 28) {
            Text(stepLabel).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
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
                if recorder.stage == .pocket {
                    Text("\(recorder.pocketCountdown)").font(.system(size: 64, weight: .semibold, design: .rounded)).monospacedDigit()
                } else {
                    pointer
                }
            }
            .frame(width: 240, height: 240)
            Text(hint).font(.headline).foregroundStyle(.secondary).frame(minHeight: 24)
            Spacer()
            if !tracker.connected && !PostureTracker.isDemo {
                Label("An AirPod is out. Put it back in to continue", systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
            }
            HStack {
                Text("\(recorder.completed)/\(recorder.total) done · \(recorder.sampleCount) samples")
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if recorder.position != nil, ![.centre, .pocket].contains(recorder.stage) {
                    Button("Skip") { recorder.skipPosition() }.buttonStyle(.bordered).tint(.primary)
                }
            }
        }
    }

    /// A: a dot that follows your head (yaw left/right, pitch up/down) relative to where you calibrated.
    private var pointer: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.35)).frame(width: 10, height: 10)
            let scale = 2.2, limit = 95.0
            let x = max(-limit, min(limit, -recorder.offsetYaw * scale))
            let y = max(-limit, min(limit, -recorder.offsetPitch * scale))
            Circle().fill(Color.primary).frame(width: 26, height: 26)
                .offset(x: x, y: y)
                .animation(.easeOut(duration: 0.12), value: recorder.offsetPitch)
        }
    }

    private var stepLabel: String {
        if recorder.stage == .pocket { return "Starting" }
        guard let p = recorder.position, recorder.stage != .centre else { return "Getting your upright position" }
        return "\(p.title) · \(recorder.rep) of \(PositionRecorder.reps)"
    }

    private var headline: String {
        switch recorder.stage {
        case .pocket: "Put your phone in your chest pocket, screen facing you"
        case .centre: recorder.pocketMode ? "Sit as you normally do and keep still" : "Sit as you normally would and look at the screen"
        case .into, .hold: recorder.position?.cue ?? ""
        case .back, .settle: "Come back to how you normally sit"
        default: ""
        }
    }

    private var hint: String {
        switch recorder.stage {
        case .centre: recorder.fill > 0 ? "Hold still…" : "Keep still to start"
        case .into: "Move into it, then hold still"
        case .hold: recorder.fill > 0 ? "Hold still…" : "Keep still"
        case .back: "Done. Come back"
        case .settle: "Hold still…"
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

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.primary)
        .foregroundStyle(Color(uiColor: .systemBackground))
    }
}
