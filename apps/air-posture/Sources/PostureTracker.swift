import CoreMotion
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

    /// Upright while the head has not dropped past the threshold (or no baseline yet).
    var isUpright: Bool { drop <= thresholdDegrees }

    /// Simulator screenshots: `-demo` feeds a slow synthetic slouch so the UI has live data.
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
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
                self.pitch = -(dropArg ?? (9 + 9 * sin(t / 4)))
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

    func calibrate() { baselinePitch = pitch }

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
        roll = motion.attitude.roll * 180 / .pi
        yaw = motion.attitude.yaw * 180 / .pi
        sampleCount += 1

        updateStillness(rotation: motion.rotationRate)
        updateFeedback()

        let r = motion.rotationRate
        let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        write(String(format: "%.3f,%@,%.2f,%.2f,%.2f,%.3f,%.2f\n",
                     Date().timeIntervalSince1970, isForeground ? "fg" : "bg",
                     pitch, roll, yaw, rate, drop))
    }

    /// Graded feedback: silent below the threshold, louder and higher the further past it.
    private func updateFeedback() {
        guard baselinePitch != nil else { feedback.level = 0; return }
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
