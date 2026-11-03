import AVFoundation

/// A continuous sine tone whose volume and pitch follow `level` (0 = silent).
/// The engine keeps running while silent: that keeps the audio session, and
/// so the app, alive in the background, which is what the spike tests.
final class FeedbackTone {
    /// 0...1. Written from the main actor, read on the audio thread; a torn
    /// read of a Double only means one buffer at a slightly wrong volume.
    var level: Double = 0

    private let engine = AVAudioEngine()
    private var phase = 0.0
    private var chimeFramesLeft = 0
    private lazy var source: AVAudioSourceNode = {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        return AVAudioSourceNode { [unowned self] _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let chiming = chimeFramesLeft > 0
            let lvl = chiming ? 0.6 : level
            let freq = chiming ? 880.0 : 330 + 330 * lvl
            let amp = Float(0.25 * lvl)
            for frame in 0..<Int(frameCount) {
                let value = amp * Float(sin(phase))
                phase += 2 * .pi * freq / sampleRate
                if phase > 2 * .pi { phase -= 2 * .pi }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            if chiming { chimeFramesLeft = max(0, chimeFramesLeft - Int(frameCount)) }
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

    /// Half-second high beep used for the "you haven't moved in a while" reminder.
    func chime() {
        chimeFramesLeft = Int(engine.outputNode.inputFormat(forBus: 0).sampleRate / 2)
    }
}
