import CoreMotion
import UserNotifications
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
    /// Head drop (degrees past calibration, + = down) sampled at 5 Hz for the last 30 s, oldest first.
    @Published private(set) var dropHistory: [Double] = []
    private var lastHistoryAppend = Date.distantPast

    private func appendHistory() {
        let now = Date()
        guard now.timeIntervalSince(lastHistoryAppend) >= 0.2 else { return }
        lastHistoryAppend = now
        dropHistory.append(drop)
        if dropHistory.count > 150 { dropHistory.removeFirst(dropHistory.count - 150) }
    }
    @Published var thresholdDegrees = UserDefaults.standard.object(forKey: "nudgeDegrees") as? Double ?? 12 {
        didSet { UserDefaults.standard.set(thresholdDegrees, forKey: "nudgeDegrees") }
    }
    static let nudgeRange = 3.0...35.0
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

    // MARK: one AirPod out
    // iOS reports which AirPod the motion comes from (sensorLocation), not whether both are in.
    // When the measuring AirPod comes out, the stream switches to the other one.

    /// On (default): taking an AirPod out pauses nudges until it's back. Off: keep tracking with the other one.
    @Published var pauseWhenAirPodOut = UserDefaults.standard.object(forKey: "pauseWhenAirPodOut") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pauseWhenAirPodOut, forKey: "pauseWhenAirPodOut") }
    }
    @Published private(set) var measuringFrom = "–"
    @Published private(set) var airPodSwitches = 0
    @Published private(set) var pausedForAirPod = false
    /// An AirPod went back in: its angle in the ear may have changed, so offer to recalibrate.
    @Published var suggestRecalibrate = false

    private func airPodBackIn() {
        suggestRecalibrate = true
        write("# AirPod back in, suggesting recalibration at \(Date().timeIntervalSince1970)\n")
        guard !isForeground else { return }
        let content = UNMutableNotificationContent()
        content.title = "AirPod back in"
        content.body = "Its angle in your ear may have changed. Open Heads Up! to recalibrate."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "recalibrate", content: content, trigger: nil))
    }

    /// Quiet (provisional) notifications need no permission prompt; they land in Notification Center.
    func requestQuietNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { _, _ in }
    }
    private var primarySensor: String?
    private var quietUntil = Date.distantPast

    /// Called with each sample's sensor before the new pitch is applied.
    private func trackSensor(_ sensor: String, previousPitch: Double, newPitch: Double) {
        defer { measuringFrom = sensor }
        guard measuringFrom != "–", sensor != measuringFrom else {
            if primarySensor == nil { primarySensor = sensor }
            return
        }
        airPodSwitches += 1
        write("# measuring AirPod changed \(measuringFrom) -> \(sensor) at \(Date().timeIntervalSince1970)\n")
        quietUntil = Date().addingTimeInterval(2)   // the switch itself produces a jump; don't nudge on it
        if pauseWhenAirPodOut {
            let wasPaused = pausedForAirPod
            pausedForAirPod = sensor != primarySensor
            if wasPaused && !pausedForAirPod { airPodBackIn() }
        } else if let b = baselinePitch {
            // same head, different ear: keep the reading continuous across the switch
            baselinePitch = b + (newPitch - previousPitch)
        }
    }

    /// Simulator screenshots: `-demo` feeds a slow synthetic slouch so the UI has live data.
    static var isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
    /// The demo was chosen in onboarding, by someone with no motion-capable AirPods to hand.
    @Published private(set) var triedDemo = false

    func tryDemo() {
        Self.isDemo = true
        triedDemo = true
        stop()
        start()
    }

    func exitDemo() {
        stop()
        Self.isDemo = false
        triedDemo = false
        connected = false
        baselinePitch = nil
        pitch = 0
        dropHistory = []
        start()
    }

    /// Demo motion that moves and holds, so the guided recorder advances in the simulator.
    static let isDemoGuide = ProcessInfo.processInfo.arguments.contains("-demoGuide")
    private var demoTimer: Timer?

    func start() {
        guard !running else { return }
        if Self.isDemo { startDemo(); return }
        openLog()
        do { try feedback.start() } catch { lastError = "Audio: \(error.localizedDescription)" }
        feedback.onResumed = { [weak self] in
            MainActor.assumeIsolated { self?.restartMotionIfStale(reason: "audio resumed") }
        }
        startMotion()
        running = true
        // watchdog: the microphone (dictation, calls) can stop both audio and motion updates
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                if !self.feedback.isRunning || self.feedback.interrupted { self.feedback.resume() }
                self.refreshSoundState()
                self.restartMotionIfStale(reason: "watchdog")
            }
        }
    }

    /// Times motion updates were restarted after stopping (e.g. after the microphone was used).
    @Published private(set) var motionRestarts = 0
    /// Whether the nudge sound can play right now; false after another app took the audio.
    @Published private(set) var soundOK = true
    @Published private(set) var audioInterruptions = 0

    /// Bring the sound back by hand (the banner's button) and confirm with a chime.
    func restoreSound() {
        feedback.resume()
        refreshSoundState()
        if soundOK { feedback.chime() }
    }

    func testChime() {
        if !feedback.isRunning { feedback.resume() }
        refreshSoundState()
        feedback.chime()
    }

    private func refreshSoundState() {
        let ok = feedback.isRunning && !feedback.interrupted
        if ok != soundOK {
            soundOK = ok
            write("# sound \(ok ? "back" : "lost") at \(Date().timeIntervalSince1970)\n")
        }
        audioInterruptions = feedback.interruptions
    }
    private var watchdog: Timer?
    private var lastSampleWall = Date()

    private func startMotion() {
        lastSampleWall = Date()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated {
                if let error { self?.lastError = error.localizedDescription }
                if let motion { self?.handle(motion) }
            }
        }
    }

    private func restartMotionIfStale(reason: String) {
        guard running, !Self.isDemo, connected, Date().timeIntervalSince(lastSampleWall) > 3 else { return }
        manager.stopDeviceMotionUpdates()
        startMotion()
        motionRestarts += 1
        write("# motion restarted (\(reason)) at \(Date().timeIntervalSince1970)\n")
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
                self.appendHistory()
                self.sampleCount += 1
                self.secondsStill = t
            }
        }
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        demoTimer?.invalidate()
        demoTimer = nil
        manager.stopDeviceMotionUpdates()
        feedback.stop()
        try? logHandle?.close()
        logHandle = nil
        running = false
    }

    /// Calibration. The person taps and looks straight ahead (sitting or standing, phone anywhere);
    /// after a grace period for that, 2 s of holding still sets the reference, confirmed by a chime and voice.
    /// that direction becomes 0°. Absolute AirPods pitch depends on how the buds sit in the ear, so it is not judged.
    func startCalibration() {
        guard !triedDemo else { return }   // simulated motion has nothing to calibrate
        if !running { start() }
        calibrationSum = 0
        calibrationCount = 0
        calibrationStill = 0
        calibrationStart = Date()
        calibrationProgress = 0
        calibrationWarning = nil
        Speaker.shared.say("Look straight ahead and keep still.")
    }

    /// Reserved for a future plausibility check; nil today.
    @Published var calibrationWarning: String?

    static let calibrationGrace = 2.0     // s to look up after tapping
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
        // (e.g. from the phone to straight ahead) can't be averaged in
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
            primarySensor = measuringFrom   // the AirPod in use when calibrating is the one "pause" waits for
            pausedForAirPod = false
            suggestRecalibrate = false
            calibrationProgress = nil
            calibrationHaptic.notificationOccurred(.success)
            feedback.chime()
            Speaker.shared.say("Set.")
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
        lastSampleWall = Date()
        if !connected { connected = true }   // samples only arrive from connected AirPods
        if !isForeground { backgroundSamples += 1 }

        let previousPitch = pitch
        let newPitch = motion.attitude.pitch * 180 / .pi
        trackSensor(MotionSample(motion).sensor, previousPitch: previousPitch, newPitch: newPitch)
        pitch = newPitch
        let r = motion.rotationRate
        lastRotationRate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        updateCalibration()
        roll = motion.attitude.roll * 180 / .pi
        yaw = motion.attitude.yaw * 180 / .pi
        sampleCount += 1

        updateStillness(rotation: motion.rotationRate)
        updateFeedback()
        appendHistory()
        onSample?(MotionSample(motion))

        write(String(format: "%.3f,%@,%.2f,%.2f,%.2f,%.3f,%.2f\n",
                     Date().timeIntervalSince1970, isForeground ? "fg" : "bg",
                     pitch, roll, yaw, lastRotationRate, drop))
    }

    /// Graded feedback: silent below the threshold, louder and higher the further past it.
    private func updateFeedback() {
        guard baselinePitch != nil, !muteFeedback, !pausedForAirPod, connected, Date() > quietUntil else { feedback.level = 0; return }
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

    /// Each launch starts a log at about 9 MB per tracked hour, so keep only the newest few.
    private func pruneLogs(keeping count: Int = 3) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: logURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        let logs = files
            .filter { $0.lastPathComponent.hasPrefix("air-posture-") && !$0.lastPathComponent.hasPrefix("air-posture-positions-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // the names carry a sortable timestamp
        for old in logs.dropFirst(count) { try? fm.removeItem(at: old) }
    }

    private func openLog() {
        pruneLogs()
        if !FileManager.default.fileExists(atPath: logURL.path) {   // pause and resume keep the same file
            FileManager.default.createFile(atPath: logURL.path, contents: Data("t,state,pitch,roll,yaw,rot_rate,drop\n".utf8))
        }
        logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()
    }

    private func write(_ line: String) {
        logHandle?.write(Data(line.utf8))
    }
}

extension PostureTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            if !self.connected && self.baselinePitch != nil { self.airPodBackIn() }
            self.connected = true
            self.write("# airpods connected\n")
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.connected = false
            self.feedback.level = 0   // the last angle must not keep the tone going (it would move to the speaker)
            self.write("# airpods disconnected, nudges paused\n")
        }
    }
}

func ease01(_ x: Double) -> Double { let c = min(max(x, 0), 1); return c * c * (3 - 2 * c) }
