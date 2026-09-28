import AVFoundation

/// Speaks settled roll totals — the legacy app's `isResultAsSpeechEnabled`
/// revived. No permissions needed; `AVSpeechSynthesizer` shares the media
/// audio session, so it obeys the silent switch like the haptic knock does.
final class SpeechController {
    private let synthesizer = AVSpeechSynthesizer()

    /// What a settled roll sounds like — pure text so tests can pin it.
    /// Speech localizes with the UI: a translated "speech.result" reads
    /// aloud in that language, and the default `AVSpeechUtterance` voice
    /// follows the resolved locale. Pinning a voice per locale is the
    /// voice-roll milestone's call — nothing here preempts it.
    static func text(for result: RollResult) -> String {
        let faces = result.faces.map(String.init).joined(
            separator: String(localized: "speech.plus",
                              defaultValue: " plus ",
                              comment: "Spoken joiner between die face values — keep the surrounding spaces"))
        return String(localized: "speech.result",
                      defaultValue: "\(faces) equals \(result.total)",
                      comment: "Spoken roll result — %1$@ is the faces joined by the ' plus ' joiner, %2$lld the total")
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
