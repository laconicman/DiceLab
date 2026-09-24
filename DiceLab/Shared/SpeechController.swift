import AVFoundation

/// Speaks settled roll totals — the legacy app's `isResultAsSpeechEnabled`
/// revived. No permissions needed; `AVSpeechSynthesizer` shares the media
/// audio session, so it obeys the silent switch like the haptic knock does.
final class SpeechController {
    private let synthesizer = AVSpeechSynthesizer()

    /// What a settled roll sounds like — pure text so tests can pin it.
    static func text(for result: RollResult) -> String {
        result.faces.map(String.init).joined(separator: " plus ")
            + " equals \(result.total)"
    }

    /// A new roll interrupts the previous utterance — the stale readout of
    /// a superseded result is worse than a clipped one.
    func speak(_ result: RollResult) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: Self.text(for: result)))
    }

    /// The toggle going off mid-sentence should mean silence now, not
    /// after the current utterance finishes.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
