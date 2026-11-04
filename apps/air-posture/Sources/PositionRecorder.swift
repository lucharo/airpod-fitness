import AVFoundation
import CoreMotion
import Foundation

/// A guided recording: spoken cues walk through each position (upright → into it → hold → back),
/// and every raw AirPods sample is written to a CSV with the position, phase and rep it belongs to.
@MainActor
final class PositionRecorder: ObservableObject {
    struct Position: Identifiable {
        let id: String
        let title: String
        let cue: String
    }

    struct Step {
        let position: Position?   // nil = baseline / finish
        let phase: String         // upright, into, hold, back
        let rep: Int
        let duration: TimeInterval
        let speech: String
    }

    /// The positions, in recording order. Controls (look up, turn, tilt) help separate "head dropped" from other moves.
    static let positions: [Position] = [
        .init(id: "phone_down", title: "Look at your phone", cue: "Pick up your phone and look down at it in your lap."),
        .init(id: "desk_down", title: "Look down at the desk", cue: "Look down at your desk or keyboard."),
        .init(id: "slouch", title: "Slouch", cue: "Slouch. Let your back round and sink into the chair."),
        .init(id: "chin_forward", title: "Chin forward", cue: "Push your chin forward toward the screen, eyes level."),
        .init(id: "lean_forward", title: "Lean in", cue: "Lean your whole body toward the screen, back straight."),
        .init(id: "recline", title: "Recline", cue: "Lean back into your chair."),
        .init(id: "look_up", title: "Look up", cue: "Look up at the ceiling."),
        .init(id: "turn_left", title: "Turn left", cue: "Turn your head to look left."),
        .init(id: "tilt_right", title: "Tilt right", cue: "Tilt your head toward your right shoulder."),
    ]

    static let reps = 2
    static let uprightHold: TimeInterval = 5
    static let transition: TimeInterval = 3
    static let positionHold: TimeInterval = 6

    @Published var isRecording = false
    @Published var finished = false
    @Published var stepIndex = 0
    @Published var secondsLeftInStep = 0
    @Published var sampleCount = 0
    @Published var fileURL: URL?

    let steps: [Step]
    var current: Step? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var totalDuration: TimeInterval { steps.reduce(0) { $0 + $1.duration } }
    var elapsedFraction: Double {
        let done = steps.prefix(stepIndex).reduce(0) { $0 + $1.duration }
        let inStep = (current?.duration ?? 0) - Double(secondsLeftInStep)
        return min(1, (done + max(0, inStep)) / totalDuration)
    }

    private let speech = AVSpeechSynthesizer()
    private var timer: Timer?
    private var stepStarted = Date()
    private var handle: FileHandle?
    private weak var tracker: PostureTracker?

    init() {
        var s: [Step] = [Step(position: nil, phase: "upright", rep: 0, duration: 8,
                              speech: "Recording starts. Sit upright and look at your screen.")]
        for p in Self.positions {
            for rep in 1...Self.reps {
                if rep > 1 || s.count > 1 {
                    s.append(Step(position: p, phase: "upright", rep: rep, duration: Self.uprightHold, speech: "Sit upright."))
                }
                s.append(Step(position: p, phase: "into", rep: rep, duration: Self.transition,
                              speech: rep == 1 ? p.cue + " Go fully into it." : p.title + "."))
                s.append(Step(position: p, phase: "hold", rep: rep, duration: Self.positionHold, speech: "Hold."))
                s.append(Step(position: p, phase: "back", rep: rep, duration: Self.transition, speech: "Back to upright."))
            }
        }
        s.append(Step(position: nil, phase: "upright", rep: 0, duration: 5, speech: "Sit upright. Last few seconds."))
        steps = s
    }

    func start(tracker: PostureTracker) {
        self.tracker = tracker
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("air-posture-positions-\(stamp).csv")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = """
        # Air Posture position recording, build \(build), \(Date())
        # protocol: reps=\(Self.reps) upright=\(Self.uprightHold)s transition=\(Self.transition)s hold=\(Self.positionHold)s
        # angles in degrees, acceleration in g, rotation in rad/s; quaternion and gravity in the headphone reference frame
        t_wall,t_sensor,position,phase,rep,qx,qy,qz,qw,pitch,roll,yaw,grav_x,grav_y,grav_z,acc_x,acc_y,acc_z,rot_x,rot_y,rot_z,sensor

        """
        FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8))
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        fileURL = url
        sampleCount = 0
        finished = false
        isRecording = true
        stepIndex = 0

        tracker.muteFeedback = true
        tracker.onSample = { [weak self] m in self?.record(m) }
        tracker.start()

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        enter(step: 0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Jump to the next position (e.g. one that hurts or doesn't apply).
    func skipPosition() {
        guard let id = current?.position?.id else { return advance(); }
        if let next = steps.indices.first(where: { $0 > stepIndex && steps[$0].position?.id != id }) {
            enter(step: next)
        }
    }

    func cancel() { finish(spoken: "Recording stopped.") }

    private func tick() {
        guard let step = current else { return }
        let left = step.duration - Date().timeIntervalSince(stepStarted)
        secondsLeftInStep = max(0, Int(left.rounded(.up)))
        if left <= 0 { advance() }
    }

    private func advance() {
        if stepIndex + 1 < steps.count { enter(step: stepIndex + 1) } else { finish(spoken: "Done. Thank you.") }
    }

    private func enter(step i: Int) {
        stepIndex = i
        stepStarted = Date()
        secondsLeftInStep = Int(steps[i].duration)
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: steps[i].speech))
    }

    private func finish(spoken: String) {
        timer?.invalidate()
        timer = nil
        tracker?.onSample = nil
        tracker?.muteFeedback = false
        try? handle?.close()
        handle = nil
        isRecording = false
        finished = true
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: spoken))
    }

    private func record(_ m: CMDeviceMotion) {
        guard isRecording, let step = current else { return }
        let q = m.attitude.quaternion, g = m.gravity, a = m.userAcceleration, r = m.rotationRate
        let deg = 180 / Double.pi
        let sensor: String = {
            switch m.sensorLocation {
            case .headphoneLeft: "left"
            case .headphoneRight: "right"
            default: "default"
            }
        }()
        let line = String(format: "%.3f,%.4f,%@,%@,%d,%.5f,%.5f,%.5f,%.5f,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%@\n",
                          Date().timeIntervalSince1970, m.timestamp, step.position?.id ?? "baseline", step.phase, step.rep,
                          q.x, q.y, q.z, q.w, m.attitude.pitch * deg, m.attitude.roll * deg, m.attitude.yaw * deg,
                          g.x, g.y, g.z, a.x, a.y, a.z, r.x, r.y, r.z, sensor)
        handle?.write(Data(line.utf8))
        sampleCount += 1
    }
}
