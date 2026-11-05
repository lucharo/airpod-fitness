import AVFoundation

/// A continuous sine tone whose volume and pitch follow `level` (0 = silent), plus a short chime.
/// The engine keeps running while silent: that keeps the audio session, and so the app and its
/// head tracking, alive in the background. Anything that takes the audio over (dictation, a call,
/// Siri) stops the engine, so it restarts itself when the interruption ends or the route changes.
final class FeedbackTone {
    /// 0...1. Written from the main actor, read on the audio thread; a torn
    /// read of a Double only means one buffer at a slightly wrong volume.
    var level: Double = 0
    /// Called after the audio came back from an interruption, so the tracker can restart motion too.
    var onResumed: (() -> Void)?
    /// True from an interruption starting (mic, call, Siri) until the audio is back.
    private(set) var interrupted = false
    private(set) var interruptions = 0

    private let engine = AVAudioEngine()
    private var sampleRate = 48_000.0
    private var phase = 0.0
    private var chimePhase = 0.0
    private var chimeFrame = -1          // -1 = not chiming
    private var chimeLength = 0
    private var attached = false
    private var observing = false
    private lazy var source: AVAudioSourceNode = {
        AVAudioSourceNode { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let sr = sampleRate
            let lvl = level
            let freq = 330 + 330 * lvl
            let amp = Float(0.25 * lvl)
            for frame in 0..<Int(frameCount) {
                var value = amp * Float(sin(phase))
                phase += 2 * .pi * freq / sr
                if phase > 2 * .pi { phase -= 2 * .pi }
                // chime: two soft notes (E5 then B5), each with a fast attack and exponential decay
                if chimeFrame >= 0 {
                    let half = max(chimeLength / 2, 1)
                    let local = chimeFrame % half
                    let note = chimeFrame < half ? 659.25 : 987.77
                    let t = Double(local) / sr
                    let env = min(1, t / 0.005) * exp(-t / 0.09)
                    value += Float(0.18 * env * sin(chimePhase))
                    chimePhase += 2 * .pi * note / sr
                    if chimePhase > 2 * .pi { chimePhase -= 2 * .pi }
                    chimeFrame += 1
                    if chimeFrame >= chimeLength { chimeFrame = -1 }
                }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
    }()

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)
        connect()
        try engine.start()
        observe()
    }

    func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Bring the audio back after something else used it. Safe to call any time.
    func resume() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            connect()
            try? engine.start()
        }
        if engine.isRunning { interrupted = false }
        onResumed?()
    }

    var isRunning: Bool { engine.isRunning }

    /// A soft two-note chime (about 0.4 s): step done, or the "time to move" reminder.
    func chime() {
        chimeLength = Int(sampleRate * 0.4)
        chimePhase = 0
        chimeFrame = 0
    }

    /// (Re)connect the tone at the output's current sample rate, which changes when the
    /// AirPods switch between music and call mode.
    private func connect() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        if !attached {
            engine.attach(source)
            attached = true
        } else {
            engine.disconnectNodeOutput(source)
        }
        engine.connect(source, to: engine.mainMixerNode, format: mono)
    }

    private func observe() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self?.interrupted = true
                self?.interruptions += 1
                return
            }
            // resume regardless of shouldResume: this app's audio is silent and mixes with others
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.resume() }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.resume() }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.resume() }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
    }
}
