import AVFoundation

/// Speaks settled roll totals — the legacy app's `isResultAsSpeechEnabled`
/// revived. No permissions needed; `AVSpeechSynthesizer` shares the media
/// audio session, so it obeys the silent switch like the haptic knock does.
@MainActor
final class SpeechController: NSObject {
    private let synthesizer: AVSpeechSynthesizer
    /// A settle that lands mid-utterance can't `speak` right away:
    /// enqueuing behind the readout would voice stale totals, and
    /// `stopSpeaking` + immediate `speak` drops the new utterance — the
    /// synthesizer won't take one in the same beat (TD-16). The newest
    /// result parks here until the delegate reports the interrupted
    /// utterance over.
    private var pending: RollResult?

    /// The synthesizer is a parameter so tests can drive the lifecycle
    /// without the real one's timing; the app always takes the default.
    init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer()) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    /// What a settled roll sounds like — pure text so tests can pin it.
    /// Just the total: "8", not "3 plus 5 equals 8" — the equation read
    /// aloud was a mouthful. Speech still localizes with the UI: a
    /// translated "speech.total" reads aloud in that language, and the
    /// default `AVSpeechUtterance` voice follows the resolved locale.
    /// Pinning a voice per locale is the voice-roll milestone's call —
    /// nothing here preempts it.
    nonisolated static func text(for result: RollResult) -> String {
        String(localized: "speech.total",
               defaultValue: "\(result.total)",
               comment: "Spoken roll result — the settled total alone")
    }

    /// A new roll interrupts the previous utterance — the stale readout of
    /// a superseded result is worse than a clipped one. `pending != nil`
    /// means a parked result is still owed its turn, so a settle inside
    /// the delegate-hop gap parks too rather than speaking ahead of it.
    func speak(_ result: RollResult) {
        guard synthesizer.isSpeaking || pending != nil else {
            trace("speak \(result.total): idle → now")
            speakNow(result)
            return
        }
        let hadPending = pending != nil
        // The Bool is "did it actually stop something" — false means no
        // didCancel is owed, which the park logic has to know about.
        let stopped = synthesizer.stopSpeaking(at: .immediate)
        pending = result
        trace("speak \(result.total): speaking=\(synthesizer.isSpeaking) hadPending=\(hadPending) stop=\(stopped) → parked")
    }

    /// The toggle going off mid-sentence should mean silence now, not
    /// after the current utterance finishes — and nothing parked speaks
    /// after it either.
    func stop() {
        let hadPending = pending != nil
        pending = nil
        synthesizer.stopSpeaking(at: .immediate)
        trace("stop: hadPending=\(hadPending)")
    }

    private func speakNow(_ result: RollResult) {
        let text = Self.text(for: result)
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        trace("speakNow \"\(text)\" session=\(session.category.rawValue) route=\(route) otherAudio=\(session.isOtherAudioPlaying)")
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    private func speakPending() {
        guard let result = pending else {
            trace("speakPending: empty")
            return
        }
        pending = nil
        trace("speakPending: release \(result.total) isSpeaking=\(synthesizer.isSpeaking)")
        speakNow(result)
    }

    /// `-speechLog` probe — see `DevFlags.speechLog`. `nonisolated` so the
    /// delegate callbacks can trace before they hop. The uptime stamp
    /// separates a dropped enqueue (instant lifecycle) from a real one.
    private nonisolated func trace(_ event: String) {
        guard DevFlags.speechLog else { return }
        print("[speech] \(String(format: "%.2f", ProcessInfo.processInfo.systemUptime)) \(event)")
    }
}

extension SpeechController: AVSpeechSynthesizerDelegate {
    /// The synthesizer reports on its own queue; `pending` is main-actor
    /// state, so every callback hops back before touching it.
    /// Fires when the synth actually starts voicing an utterance — the
    /// "did audio happen" signal `didFinish` can't give (it fires even
    /// for a silently dropped enqueue).
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        trace("willSpeak \"\(utterance.speechString)\"")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        trace("delegate didFinish \"\(utterance.speechString)\"")
        utteranceEnded()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        trace("delegate didCancel \"\(utterance.speechString)\"")
        utteranceEnded()
    }

    private nonisolated func utteranceEnded() {
        Task { @MainActor in self.speakPending() }
    }
}
