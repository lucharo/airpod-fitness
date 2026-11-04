import AVFoundation

/// A continuous sine tone whose volume and pitch follow `level` (0 = silent), plus a short chime.
/// The engine keeps running while silent: that keeps the audio session, and
/// so the app, alive in the background, which is what the spike tests.
final class FeedbackTone {
    /// 0...1. Written from the main actor, read on the audio thread; a torn
    /// read of a Double only means one buffer at a slightly wrong volume.
    var level: Double = 0

    private let engine = AVAudioEngine()
    private var phase = 0.0
    private var chimePhase = 0.0
    private var chimeFrame = -1          // -1 = not chiming
    private var chimeLength = 0
    private lazy var source: AVAudioSourceNode = {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        return AVAudioSourceNode { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let lvl = level
            let freq = 330 + 330 * lvl
            let amp = Float(0.25 * lvl)
            for frame in 0..<Int(frameCount) {
                var value = amp * Float(sin(phase))
                phase += 2 * .pi * freq / sampleRate
                if phase > 2 * .pi { phase -= 2 * .pi }
                // chime: two soft notes (E5 then B5), each with a fast attack and exponential decay
                if chimeFrame >= 0 {
                    let half = chimeLength / 2
                    let local = chimeFrame % half
                    let note = chimeFrame < half ? 659.25 : 987.77
                    let t = Double(local) / sampleRate
                    let env = min(1, t / 0.005) * exp(-t / 0.09)
                    value += Float(0.18 * env * sin(chimePhase))
                    chimePhase += 2 * .pi * note / sampleRate
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
        let format = engine.outputNode.inputFormat(forBus: 0)
        let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        try engine.start()
    }

    func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A soft two-note chime (about 0.4 s): step done, or the "time to move" reminder.
    func chime() {
        chimeLength = Int(engine.outputNode.inputFormat(forBus: 0).sampleRate * 0.4)
        chimePhase = 0
        chimeFrame = 0
    }
}
