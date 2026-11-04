import CoreMotion
import UIKit
import Foundation

/// Reads AirPods head motion, compares pitch with a calibrated baseline,
/// drives graded audio feedback, and logs every sample so a background run
/// can be checked afterwards for gaps.
@MainActor
final class PostureTracker: NSObject, ObservableObject {
    @Published var available = false
    @Published var connected = false
    @Published var running = false
    @Published var pitch = 0.0   // degrees
    @Published var roll = 0.0
    @Published var yaw = 0.0
    @Published var baselinePitch: Double?
    /// 0...1 while a 2-second recalibration is collecting samples; nil otherwise.
    @Published var calibrationProgress: Double?
    @Published var calibratedAt: Date?
    @Published var thresholdDegrees = 12.0
    @Published var sampleCount = 0
    @Published var longestBackgroundGap = 0.0          // seconds
    @Published var backgroundSamples = 0
    @Published var secondsStill = 0.0
    @Published var stillReminderMinutes = 30.0
    @Published var lastError: String?

    /// Degrees the head has dropped forward past the baseline (positive = down).
    var drop: Double { baselinePitch.map { $0 - pitch } ?? 0 }

    let logURL: URL
    private let manager = CMHeadphoneMotionManager()
    private let feedback = FeedbackTone()
    private var isForeground = true
    private var lastSampleTime: TimeInterval?
    private var lastMovementTime = Date()
    private var lastMovementPitch = 0.0
    private var lastReminder = Date.distantPast
    private var logHandle: FileHandle?

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        logURL = docs.appendingPathComponent("air-posture-\(stamp).csv")
        super.init()
        manager.delegate = self
        available = manager.isDeviceMotionAvailable
    }

    /// Raw samples for the position recorder; nil when nothing is recording.
    var onSample: ((MotionSample) -> Void)?
    /// Silences the posture tone while the recorder runs.
    var muteFeedback = false

    /// Upright while the head has not dropped past the threshold (or no baseline yet).
    var isUpright: Bool { drop <= thresholdDegrees }

    /// Simulator screenshots: `-demo` feeds a slow synthetic slouch so the UI has live data.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    /// Demo motion that moves and holds, so the guided recorder advances in the simulator.
    static let isDemoGuide = ProcessInfo.processInfo.arguments.contains("-demoGuide")
    private var demoTimer: Timer?

    func start() {
        guard !running else { return }
        if Self.isDemo { startDemo(); return }
        openLog()
        do { try feedback.start() } catch { lastError = "Audio: \(error.localizedDescription)" }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated {
                if let error { self?.lastError = error.localizedDescription }
                if let motion { self?.handle(motion) }
            }
        }
        running = true
    }

    private func startDemo() {
        available = true
        connected = true
        running = true
        baselinePitch = 0
        let dropArg = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoDrop")
            .flatMap { i in Double(ProcessInfo.processInfo.arguments[i + 1]) }
        let t0 = Date()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date().timeIntervalSince(t0)
                if Self.isDemoGuide {
                    // alternate: 4 s still at centre, 4 s still 30 degrees down, with 1 s moves between
                    let phase = t.truncatingRemainder(dividingBy: 8)
                    let k = phase < 3 ? 0 : phase < 4 ? ease01(phase - 3) : phase < 7 ? 1 : 1 - ease01(phase - 7)
                    let previous = self.pitch
                    self.pitch = -30 * k
                    var sample = MotionSample(tSensor: t)
                    sample.pitch = self.pitch
                    sample.rotX = (self.pitch - previous) / 0.1 * .pi / 180
                    self.onSample?(sample)
                } else {
                    self.pitch = -(dropArg ?? (9 + 9 * sin(t / 4)))
                }
                self.updateCalibration()
                self.sampleCount += 1
                self.secondsStill = t
            }
        }
    }

    func stop() {
        demoTimer?.invalidate()
        demoTimer = nil
        manager.stopDeviceMotionUpdates()
        feedback.stop()
        try? logHandle?.close()
        logHandle = nil
        running = false
    }

    /// Hands-free calibration. The person taps, puts the phone down and looks at their monitor;
    /// after a grace period for that, 2 s of holding still sets the reference, confirmed by a chime and voice.
    /// The reference is "eyes on the monitor, sitting tall", never a moment of looking at the phone.
    func startCalibration() {
        if !running { start() }
        calibrationSum = 0
        calibrationCount = 0
        calibrationStill = 0
        calibrationStart = Date()
        calibrationProgress = 0
        calibrationWarning = nil
        Speaker.shared.say("Put the phone down. Look at your monitor and sit tall.")
    }

    /// Set when the captured reference looks like looking down rather than at a monitor.
    @Published var calibrationWarning: String?

    static let calibrationGrace = 3.0     // s to put the phone down and look up
    static let calibrationHold = 2.0      // s of stillness that sets the reference
    private var calibrationSum = 0.0, calibrationCount = 0.0, calibrationStill = 0.0
    private var calibrationMin = 0.0, calibrationMax = 0.0
    private var calibrationStart = Date()
    private var lastCalibrationSample: Date?
    private var lastRotationRate = 0.0
    private let calibrationHaptic = UINotificationFeedbackGenerator()

    private func updateCalibration() {
        guard calibrationProgress != nil else { return }
        let now = Date()
        let dt = lastCalibrationSample.map { min(now.timeIntervalSince($0), 0.2) } ?? 0
        lastCalibrationSample = now
        guard now.timeIntervalSince(calibrationStart) > Self.calibrationGrace else { return }
        // still = slow rotation AND the head stays within a 3° pitch band, so a slow lift
        // from the phone to the monitor can't be averaged in
        if calibrationCount == 0 { calibrationMin = pitch; calibrationMax = pitch }
        let lo = min(calibrationMin, pitch), hi = max(calibrationMax, pitch)
        if lastRotationRate < 0.1 && hi - lo < 3 {
            calibrationMin = lo
            calibrationMax = hi
            calibrationSum += pitch
            calibrationCount += 1
            calibrationStill += dt
        } else {
            calibrationSum = 0
            calibrationCount = 0
            calibrationStill = 0
        }
        calibrationProgress = min(calibrationStill / Self.calibrationHold, 0.999)
        if calibrationStill >= Self.calibrationHold {
            let value = calibrationSum / max(calibrationCount, 1)
            baselinePitch = value
            calibratedAt = now
            calibrationProgress = nil
            calibrationHaptic.notificationOccurred(.success)
            feedback.chime()
            if value < -15 {
                calibrationWarning = "That looked like your head was tilted down. If you were looking at the phone, recalibrate while looking at your monitor."
                Speaker.shared.say("Set, but your head looked tilted down. Check the phone.")
            } else {
                Speaker.shared.say("Set.")
            }
        }
    }

    /// Soft two-note chime through the AirPods.
    func chime() { feedback.chime() }

    func appStateChanged(isForeground: Bool) {
        self.isForeground = isForeground
        write("# state \(isForeground ? "foreground" : "background") at \(Date().timeIntervalSince1970)\n")
    }

    private func handle(_ motion: CMDeviceMotion) {
        let now = motion.timestamp
        if let last = lastSampleTime, !isForeground {
            longestBackgroundGap = max(longestBackgroundGap, now - last)
        }
        lastSampleTime = now
        if !isForeground { backgroundSamples += 1 }

        pitch = motion.attitude.pitch * 180 / .pi
        let r = motion.rotationRate
        lastRotationRate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        updateCalibration()
        roll = motion.attitude.roll * 180 / .pi
        yaw = motion.attitude.yaw * 180 / .pi
        sampleCount += 1

        updateStillness(rotation: motion.rotationRate)
        updateFeedback()
        onSample?(MotionSample(motion))

        write(String(format: "%.3f,%@,%.2f,%.2f,%.2f,%.3f,%.2f\n",
                     Date().timeIntervalSince1970, isForeground ? "fg" : "bg",
                     pitch, roll, yaw, lastRotationRate, drop))
    }

    /// Graded feedback: silent below the threshold, louder and higher the further past it.
    private func updateFeedback() {
        guard baselinePitch != nil, !muteFeedback else { feedback.level = 0; return }
        let excess = drop - thresholdDegrees
        feedback.level = excess > 0 ? min(1, excess / 20) : 0
    }

    /// Movement = a noticeable head turn or a 10 degree change in pitch since the last movement.
    private func updateStillness(rotation r: CMRotationRate) {
        let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        if rate > 0.8 || abs(pitch - lastMovementPitch) > 10 {
            lastMovementTime = Date()
            lastMovementPitch = pitch
        }
        secondsStill = Date().timeIntervalSince(lastMovementTime)
        if secondsStill > stillReminderMinutes * 60, Date().timeIntervalSince(lastReminder) > 300 {
            lastReminder = Date()
            feedback.chime()
        }
    }

    private func openLog() {
        FileManager.default.createFile(atPath: logURL.path, contents: Data("t,state,pitch,roll,yaw,rot_rate,drop\n".utf8))
        logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()
    }

    private func write(_ line: String) {
        logHandle?.write(Data(line.utf8))
    }
}

extension PostureTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.connected = true; self.write("# airpods connected\n") }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in self.connected = false; self.write("# airpods disconnected\n") }
    }
}

func ease01(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
