import Foundation
import UIKit

/// Guided recording driven by your head, not a timer (in the spirit of Face ID enrolment):
/// you move into a position, a ring fills while you hold still, it chimes and waits for you to
/// come back, then moves on. Every raw sample goes to a CSV labelled with position, phase and rep.
@MainActor
final class PositionRecorder: ObservableObject {
    struct Position: Identifiable {
        let id: String
        let title: String
        let cue: String
    }

    enum Stage: Equatable {
        case intro, centre, into, hold, back, settle, done
    }

    static let positions: [Position] = [
        .init(id: "phone_down", title: "Look at your phone", cue: "Pick up your phone and look at it in your lap"),
        .init(id: "desk_down", title: "Look down at the desk", cue: "Look down at your desk or keyboard"),
        .init(id: "slouch", title: "Slouch", cue: "Let your back round and sink into the chair"),
        .init(id: "chin_forward", title: "Chin forward", cue: "Push your chin toward the screen, eyes level"),
        .init(id: "lean_forward", title: "Lean in", cue: "Lean your whole body toward the screen"),
        .init(id: "recline", title: "Recline", cue: "Lean back into your chair"),
        .init(id: "look_up", title: "Look up", cue: "Look up at the ceiling"),
        .init(id: "turn_left", title: "Turn left", cue: "Turn your head to look left"),
        .init(id: "tilt_right", title: "Tilt right", cue: "Tilt your head toward your right shoulder"),
    ]
    static let reps = 2

    // Thresholds from the first recording (2026-11-04): holds had pitch SD 0.1–1.7°, deliberate moves were ≥ 4°.
    static let stillRotation = 0.25      // rad/s
    static let stillAcceleration = 0.05  // g
    static let movedDegrees = 6.0
    static let movedAcceleration = 0.08  // g; catches translations (chin forward) with little rotation
    static let assumeMovedAfter = 4.0    // s; some positions barely rotate the head
    static let centreHold = 2.0, positionHold = 3.0, settleHold = 1.0

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var index = 0          // position index
    @Published private(set) var rep = 1
    @Published private(set) var fill = 0.0         // 0...1 progress of the current hold
    @Published private(set) var completed = 0      // position-reps completed
    @Published private(set) var offsetPitch = 0.0  // live head pose relative to the centre, degrees
    @Published private(set) var offsetYaw = 0.0
    @Published private(set) var offsetRoll = 0.0
    @Published private(set) var sampleCount = 0
    @Published private(set) var fileURL: URL?

    var position: Position? { Self.positions.indices.contains(index) ? Self.positions[index] : nil }
    var total: Int { Self.positions.count * Self.reps }
    var isRecording: Bool { ![.intro, .done].contains(stage) }

    private weak var tracker: PostureTracker?
    private var handle: FileHandle?
    private var centre = (pitch: 0.0, yaw: 0.0, roll: 0.0)
    private var centreSum = (pitch: 0.0, yaw: 0.0, roll: 0.0, n: 0.0)
    private var anchor = (pitch: 0.0, yaw: 0.0, roll: 0.0)   // absolute pose when the stage began
    private var current = (pitch: 0.0, yaw: 0.0, roll: 0.0)
    private var moved = false
    private var stageStartT: TimeInterval?
    private var lastT: TimeInterval?
    private let haptic = UINotificationFeedbackGenerator()
    private let tap = UIImpactFeedbackGenerator(style: .light)

    func start(tracker: PostureTracker) {
        self.tracker = tracker
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("air-posture-positions-\(stamp).csv")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = """
        # Air Posture position recording, build \(build), \(Date())
        # guided by motion: reps=\(Self.reps) centreHold=\(Self.centreHold)s positionHold=\(Self.positionHold)s settleHold=\(Self.settleHold)s stillRotation=\(Self.stillRotation)rad/s movedDegrees=\(Self.movedDegrees)
        # phases: upright (settled before a position), into (moving in), hold (still in position), back (returning)
        # angles in degrees, acceleration in g, rotation in rad/s; quaternion and gravity in the headphone reference frame
        t_wall,t_sensor,position,phase,rep,qx,qy,qz,qw,pitch,roll,yaw,grav_x,grav_y,grav_z,acc_x,acc_y,acc_z,rot_x,rot_y,rot_z,sensor

        """
        FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8))
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        fileURL = url
        sampleCount = 0
        completed = 0
        index = 0
        rep = 1
        lastT = nil
        centreSum = (0, 0, 0, 0)
        enter(.centre)
        tracker.muteFeedback = true
        tracker.onSample = { [weak self] s in self?.handle(s) }
        tracker.start()
    }

    func skipPosition() {
        guard position != nil, isRecording else { return }
        completed += Self.reps - rep + 1
        rep = 1
        index += 1
        if index >= Self.positions.count { finish() } else { enter(.into) }
    }

    func stop() { finish() }

    // MARK: state machine

    private func enter(_ s: Stage) {
        stage = s
        fill = 0
        moved = false
        stageStartT = nil
        anchor = current
    }

    private func handle(_ s: MotionSample) {
        guard isRecording else { return }
        let dt = lastT.map { min(max(s.tSensor - $0, 0), 0.2) } ?? 0
        lastT = s.tSensor
        if stageStartT == nil { stageStartT = s.tSensor }
        let elapsed = s.tSensor - (stageStartT ?? s.tSensor)
        let still = s.rotationRate < Self.stillRotation && s.acceleration < Self.stillAcceleration
        current = (s.pitch, s.yaw, s.roll)
        offsetPitch = s.pitch - centre.pitch
        offsetYaw = wrap(s.yaw - centre.yaw)
        offsetRoll = s.roll - centre.roll
        if distance(current, anchor) > Self.movedDegrees || s.acceleration > Self.movedAcceleration
            || elapsed > Self.assumeMovedAfter {
            moved = true
        }

        write(s)

        switch stage {
        case .centre:
            if still {
                centreSum = (centreSum.pitch + s.pitch, centreSum.yaw + s.yaw, centreSum.roll + s.roll, centreSum.n + 1)
                fill += dt / Self.centreHold
            } else {
                centreSum = (0, 0, 0, 0)
                fill = 0
            }
            if fill >= 1 {
                let n = max(centreSum.n, 1)
                centre = (centreSum.pitch / n, centreSum.yaw / n, centreSum.roll / n)
                tap.impactOccurred()
                enter(.into)
            }
        case .into:
            if moved && still && elapsed > 1 { enter(.hold) }
        case .hold:
            fill = still ? fill + dt / Self.positionHold : max(0, fill - dt / Self.positionHold)
            if fill >= 1 {
                haptic.notificationOccurred(.success)
                tracker?.chime()
                enter(.back)
            }
        case .back:
            if moved && still && elapsed > 0.8 { enter(.settle) }
        case .settle:
            fill = still ? fill + dt / Self.settleHold : 0
            if fill >= 1 { next() }
        case .intro, .done:
            break
        }
    }

    private func next() {
        completed += 1
        if rep < Self.reps { rep += 1 } else { rep = 1; index += 1 }
        if index >= Self.positions.count { finish() } else { tap.impactOccurred(); enter(.into) }
    }

    private func finish() {
        guard stage != .done else { return }
        tracker?.onSample = nil
        tracker?.muteFeedback = false
        try? handle?.close()
        handle = nil
        stage = .done
        haptic.notificationOccurred(.success)
        tracker?.chime()
    }

    // MARK: CSV

    /// "settle" is the upright reference for the position/rep that comes next, so it carries that label.
    private var label: (position: String, phase: String, rep: Int) {
        switch stage {
        case .centre:
            return ("baseline", "upright", 0)
        case .settle:
            var (i, r) = (index, rep + 1)
            if r > Self.reps { r = 1; i += 1 }
            return (Self.positions.indices.contains(i) ? Self.positions[i].id : "baseline", "upright", r)
        default:
            return (position?.id ?? "baseline", stage == .hold ? "hold" : stage == .back ? "back" : "into", rep)
        }
    }

    private func write(_ s: MotionSample) {
        let l = label
        let line = String(format: "%.3f,%.4f,%@,%@,%d,%.5f,%.5f,%.5f,%.5f,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%@\n",
                          Date().timeIntervalSince1970, s.tSensor, l.position, l.phase, l.rep,
                          s.qx, s.qy, s.qz, s.qw, s.pitch, s.roll, s.yaw,
                          s.gravX, s.gravY, s.gravZ, s.accX, s.accY, s.accZ, s.rotX, s.rotY, s.rotZ, s.sensor)
        handle?.write(Data(line.utf8))
        sampleCount += 1
    }

    private func wrap(_ d: Double) -> Double {
        var x = d
        while x > 180 { x -= 360 }
        while x < -180 { x += 360 }
        return x
    }

    private func distance(_ a: (pitch: Double, yaw: Double, roll: Double),
                          _ b: (pitch: Double, yaw: Double, roll: Double)) -> Double {
        let dp = a.pitch - b.pitch, dy = wrap(a.yaw - b.yaw), dr = a.roll - b.roll
        return (dp * dp + dy * dy + dr * dr).squareRoot()
    }
}
