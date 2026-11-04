import AVFoundation

/// Short spoken cues for moments when the screen is out of sight, in the best installed voice
/// (an Enhanced or Premium voice if the person has downloaded one in Settings → Accessibility → Spoken Content).
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == lang }
            .max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: lang)
    }()

    func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}
