import CoreMotion
import Foundation
import UIKit

/// Guided recording that never needs the phone in your hand once started.
/// The phone sits on the desk (or in a chest pocket); cues are spoken; the app watches your head:
/// you move into a position, hold still until the chime, come back, and the next cue follows.
/// Every raw sample goes to a CSV labelled with position, phase and rep.
@MainActor
final class PositionRecorder: ObservableObject {
    struct Position: Identifiable {
        let id: String
        let title: String
        let cue: String
    }

    enum Stage: Equatable {
        case intro, placing, usual, into, hold, back, rest, done
    }

    /// Same nine positions in both modes, so recordings are comparable.
    static let positions: [Position] = [
        .init(id: "lap_down", title: "Look at your lap", cue: "Look down at your lap, as if reading your phone"),
        .init(id: "desk_down", title: "Look at the desk", cue: "Look down at your desk or keyboard"),
        .init(id: "slouch", title: "Slouch", cue: "Slouch. Let your back round and sink into the chair"),
        .init(id: "chin_forward", title: "Chin forward", cue: "Push your chin forward, eyes level"),
        .init(id: "lean_forward", title: "Lean in", cue: "Lean your whole body forward"),
        .init(id: "recline", title: "Recline", cue: "Lean back into your chair"),
        .init(id: "look_up", title: "Look up", cue: "Look up at the ceiling"),
        .init(id: "turn_left", title: "Turn left", cue: "Turn your head to look left"),
        .init(id: "tilt_right", title: "Tilt right", cue: "Tilt your head toward your right shoulder"),
    ]
    static let reps = 2

    // Thresholds from the first recording (2026-11-04): holds had pitch SD 0.1–1.7°, deliberate moves were ≥ 4°.
    static let stillRotation = 0.25        // rad/s, AirPods
    static let stillAcceleration = 0.05    // g, AirPods
    static let movedDegrees = 6.0          // head
    static let movedAcceleration = 0.08    // g; catches translations (chin forward) with little rotation
    static let movedTrunkDegrees = 4.0     // pocket mode: phone tilt
    static let assumeMovedAfter = 6.0      // s; last resort when nothing registers (logged as moved_by=timeout)
    static let usualHold = 2.0, positionHold = 3.0, restHold = 1.0
    static let placingStill = 2.0          // s of phone stillness that means "it's in place"
    static let usualGrace = 3.0            // s after placing before "usual" can be captured (time to look up)

    @Published var pocketMode = false
    @Published private(set) var stage: Stage = .intro
    @Published private(set) var index = 0
    @Published private(set) var rep = 1
    @Published private(set) var fill = 0.0
    @Published private(set) var completed = 0
    @Published private(set) var offsetPitch = 0.0
    @Published private(set) var offsetYaw = 0.0
    @Published private(set) var sampleCount = 0
    @Published private(set) var fileURL: URL?

    var position: Position? { Self.positions.indices.contains(index) ? Self.positions[index] : nil }
    var total: Int { Self.positions.count * Self.reps }
    var isRecording: Bool { ![.intro, .done].contains(stage) }
    var hasCentre: Bool { ![.intro, .placing, .usual].contains(stage) }

    private weak var tracker: PostureTracker?
    private var handle: FileHandle?
    private var centre = (pitch: 0.0, yaw: 0.0, roll: 0.0)
    private var centreSum = (pitch: 0.0, yaw: 0.0, roll: 0.0, n: 0.0)
    private var current = (pitch: 0.0, yaw: 0.0, roll: 0.0)
    private var anchor = (pitch: 0.0, yaw: 0.0, roll: 0.0)
    private var trunkAnchor: CMAcceleration?
    private var movedBy: String?
    private var lastStill = false
    private var usualMin = 0.0, usualMax = 0.0
    private var stageStartT: TimeInterval?
    private var lastT: TimeInterval?
    private let phoneMotion = CMMotionManager()
    private var phone: CMDeviceMotion?
    private var phoneStill = 0.0
    private var phoneMoved = false
    private var placingTimer: Timer?
    private let haptic = UINotificationFeedbackGenerator()
    private let say = Speaker.shared

    func start(tracker: PostureTracker) {
        self.tracker = tracker
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = docs.appendingPathComponent("air-posture-positions-\(stamp).csv")
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = """
        # Air Posture position recording, build \(build), \(Date()), mode=\(pocketMode ? "pocket" : "desk")
        # reps=\(Self.reps) usualHold=\(Self.usualHold)s positionHold=\(Self.positionHold)s restHold=\(Self.restHold)s stillRotation=\(Self.stillRotation)rad/s movedDegrees=\(Self.movedDegrees)
        # position "usual" = how you usually sit, looking straight ahead. phases: rest (settled before a position), into, hold, back.
        # still = AirPods still on this sample; moved_by = what first registered the move (angle, accel, trunk, timeout)
        # angles in degrees, acceleration in g, rotation in rad/s; ph_* = iPhone in a chest pocket (pocket mode only)
        t_wall,t_sensor,position,phase,rep,still,moved_by,qx,qy,qz,qw,pitch,roll,yaw,grav_x,grav_y,grav_z,acc_x,acc_y,acc_z,rot_x,rot_y,rot_z,sensor,ph_pitch,ph_roll,ph_yaw,ph_grav_x,ph_grav_y,ph_grav_z,ph_acc_x,ph_acc_y,ph_acc_z

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
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isProximityMonitoringEnabled = pocketMode
        tracker.muteFeedback = true
        tracker.onSample = { [weak self] s in self?.handle(s) }
        tracker.start()
        startPhoneMotion()
        enter(.placing)
        say.say(pocketMode ? "Put the phone in your chest pocket, screen facing you."
                           : "Put the phone down on the desk. You won't need to look at it.")
        // the phone settling (moved, then still) means it's in place; 20 s fallback
        let started = Date()
        placingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.stage == .placing else { return }
                let placed = self.phoneMoved && self.phoneStill >= Self.placingStill && self.phoneInPlace
                let timedOut = Date().timeIntervalSince(started) > 20
                if placed || timedOut {
                    self.placingTimer?.invalidate()
                    self.handle?.write(Data("# placing ended by \(placed ? "detection" : "20 s fallback")\n".utf8))
                    self.say.say("Sit as you usually do, looking straight ahead. Hold still.")
                    self.enter(.usual)
                }
            }
        }
    }

    func skipPosition() {
        guard position != nil, hasCentre else { return }
        completed += Self.reps - rep + 1
        rep = 1
        index += 1
        if index >= Self.positions.count { finish() } else { cue(); enter(.into) }
    }

    func stop() { finish() }

    // MARK: state machine

    private func enter(_ s: Stage) {
        stage = s
        fill = 0
        if s != .rest { movedBy = nil }
        stageStartT = nil
        anchor = current
        trunkAnchor = phone?.gravity
    }

    private func cue() {
        guard let p = position else { return }
        say.say(rep == 1 ? p.cue + "." : p.title + ", again.")
    }

    private func handle(_ s: MotionSample) {
        guard isRecording else { return }
        let dt = lastT.map { min(max(s.tSensor - $0, 0), 0.2) } ?? 0
        lastT = s.tSensor
        if stageStartT == nil { stageStartT = s.tSensor }
        let elapsed = s.tSensor - (stageStartT ?? s.tSensor)
        let still = s.rotationRate < Self.stillRotation && s.acceleration < Self.stillAcceleration
        lastStill = still
        current = (s.pitch, s.yaw, s.roll)
        offsetPitch = s.pitch - centre.pitch
        offsetYaw = wrap(s.yaw - centre.yaw)

        if movedBy == nil {
            if distance(current, anchor) > Self.movedDegrees { movedBy = "angle" }
            else if s.acceleration > Self.movedAcceleration { movedBy = "accel" }
            else if pocketMode, let a = trunkAnchor, let g = phone?.gravity, angle(a, g) > Self.movedTrunkDegrees { movedBy = "trunk" }
            else if elapsed > Self.assumeMovedAfter { movedBy = "timeout" }
        }

        write(s)

        switch stage {
        case .usual:
            guard elapsed > Self.usualGrace else { break }
            if centreSum.n == 0 { usualMin = s.pitch; usualMax = s.pitch }
            let lo = min(usualMin, s.pitch), hi = max(usualMax, s.pitch)
            if still && s.rotationRate < 0.1 && hi - lo < 3 {
                usualMin = lo
                usualMax = hi
                centreSum = (centreSum.pitch + s.pitch, centreSum.yaw + s.yaw, centreSum.roll + s.roll, centreSum.n + 1)
                fill += dt / Self.usualHold
            } else {
                centreSum = (0, 0, 0, 0)
                fill = 0
            }
            if fill >= 1 {
                let n = max(centreSum.n, 1)
                centre = (centreSum.pitch / n, centreSum.yaw / n, centreSum.roll / n)
                haptic.notificationOccurred(.success)
                cue()
                enter(.into)
            }
        case .into:
            if movedBy != nil && still && elapsed > 1 { enter(.hold) }
        case .hold:
            fill = still ? fill + dt / Self.positionHold : 0
            if fill >= 1 {
                haptic.notificationOccurred(.success)
                tracker?.chime()
                say.say("Come back.")
                enter(.back)
            }
        case .back:
            if movedBy != nil && still && elapsed > 0.8 { enter(.rest) }
        case .rest:
            fill = still ? fill + dt / Self.restHold : 0
            if fill >= 1 { next() }
        case .intro, .placing, .done:
            break
        }
    }

    private func next() {
        completed += 1
        if rep < Self.reps { rep += 1 } else { rep = 1; index += 1 }
        if index >= Self.positions.count { finish() } else { cue(); enter(.into) }
    }

    private func finish() {
        guard stage != .done else { return }
        tracker?.onSample = nil
        tracker?.muteFeedback = false
        placingTimer?.invalidate()
        phoneMotion.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.isProximityMonitoringEnabled = false
        try? handle?.close()
        handle = nil
        let wasRunning = stage != .intro
        stage = .done
        if wasRunning {
            haptic.notificationOccurred(.success)
            say.say("All done. Thank you.")
        }
    }

    // MARK: CSV

    /// "rest" is the settled reference for the position/rep that comes next, so it carries that label.
    private var label: (position: String, phase: String, rep: Int) {
        switch stage {
        case .placing: return ("setup", "placing", 0)
        case .usual: return ("usual", "hold", 0)
        case .rest:
            var (i, r) = (index, rep + 1)
            if r > Self.reps { r = 1; i += 1 }
            return (Self.positions.indices.contains(i) ? Self.positions[i].id : "end", "rest", r)
        case .hold: return (position?.id ?? "end", "hold", rep)
        case .back: return (position?.id ?? "end", "back", rep)
        default: return (position?.id ?? "end", "into", rep)
        }
    }

    private func write(_ s: MotionSample) {
        let l = label
        var line = String(format: "%.3f,%.4f,%@,%@,%d,%d,%@,%.5f,%.5f,%.5f,%.5f,%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%@",
                          Date().timeIntervalSince1970, s.tSensor, l.position, l.phase, l.rep, lastStill ? 1 : 0, movedBy ?? "",
                          s.qx, s.qy, s.qz, s.qw, s.pitch, s.roll, s.yaw,
                          s.gravX, s.gravY, s.gravZ, s.accX, s.accY, s.accZ, s.rotX, s.rotY, s.rotZ, s.sensor)
        if pocketMode, let m = phone {
            let deg = 180 / Double.pi
            line += String(format: ",%.2f,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
                           m.attitude.pitch * deg, m.attitude.roll * deg, m.attitude.yaw * deg,
                           m.gravity.x, m.gravity.y, m.gravity.z,
                           m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
        } else {
            line += ",,,,,,,,,"
        }
        handle?.write(Data((line + "\n").utf8))
        sampleCount += 1
    }

    // MARK: phone motion (placement detection, and the trunk in pocket mode)

    private func startPhoneMotion() {
        phoneMoved = false
        phoneStill = 0
        guard phoneMotion.isDeviceMotionAvailable else { phoneMoved = true; phoneStill = Self.placingStill; return }
        phoneMotion.deviceMotionUpdateInterval = 1.0 / 50
        phoneMotion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            MainActor.assumeIsolated {
                guard let self, let m else { return }
                self.phone = m
                let r = m.rotationRate, a = m.userAcceleration
                let rot = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
                let acc = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
                if rot > 0.5 || acc > 0.1 { self.phoneMoved = true }
                self.phoneStill = (rot < 0.15 && acc < 0.03) ? self.phoneStill + 0.02 : 0
            }
        }
    }

    /// Desk: lying flat. Pocket: roughly upright. A phone held in the hand at reading angle is neither.
    private var phoneInPlace: Bool {
        guard let g = phone?.gravity else { return true }
        return pocketMode ? abs(g.y) > 0.6 : abs(g.z) > 0.8
    }

    private func angle(_ a: CMAcceleration, _ b: CMAcceleration) -> Double {
        let dot = a.x * b.x + a.y * b.y + a.z * b.z
        let na = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), nb = (b.x * b.x + b.y * b.y + b.z * b.z).squareRoot()
        return acos(max(-1, min(1, dot / max(na * nb, 1e-9)))) * 180 / .pi
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
