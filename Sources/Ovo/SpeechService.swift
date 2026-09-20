import AVFoundation
import Combine

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()
    @Published private(set) var speakingText: String?
    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, languageCode: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let wasSame = speakingText == text && synthesizer.isSpeaking
        synthesizer.stopSpeaking(at: .immediate)
        speakingText = nil
        guard !wasSame else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speakingText = text
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            if self?.speakingText == utterance.speechString { self?.speakingText = nil }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            if self?.speakingText == utterance.speechString { self?.speakingText = nil }
        }
    }
}
