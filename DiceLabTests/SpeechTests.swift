import AVFoundation
import Testing
@testable import DiceLab

/// SpeechController's pins: the spoken text, and the park/release
/// lifecycle TD-16 turned on — driven through a mock synthesizer so the
/// timing is the test's, not the framework's.
@MainActor
struct SpeechTests {

    /// The speech format is user-facing prose — pin it so a refactor can't
    /// quietly grow "7" back into the equation readout.
    @Test("speech text reads the total")
    func speechText() {
        #expect(SpeechController.text(for: RollResult(faces: [3, 3, 1])) == "7")
        #expect(SpeechController.text(for: RollResult(faces: [6])) == "6")
    }

    /// The bug's case: a settle while the previous total is still
    /// speaking. The new result must park — not drop, not queue — and
    /// speak once the synth reports the interruption over.
    @Test("a settle mid-utterance parks, then speaks on cancel")
    func parksThenSpeaks() async {
        let synth = MockSynthesizer()
        let speech = SpeechController(synthesizer: synth)

        speech.speak(RollResult(faces: [6]))
        #expect(synth.spoken == ["6"])
        #expect(synth.stops == 0)

        speech.speak(RollResult(faces: [6]))
        #expect(synth.spoken == ["6"])  // parked: neither dropped nor voiced early
        #expect(synth.stops == 1)

        synth.cancel()
        await drain()
        #expect(synth.spoken == ["6", "6"])
        #expect(synth.stops == 1)
    }

    /// Settles inside one utterance replace the parked result — only the
    /// newest total is owed a readout, never a queue of stale ones.
    @Test("a newer settle replaces the parked one")
    func newestWins() async {
        let synth = MockSynthesizer()
        let speech = SpeechController(synthesizer: synth)

        speech.speak(RollResult(faces: [6]))
        speech.speak(RollResult(faces: [5]))
        speech.speak(RollResult(faces: [4]))
        #expect(synth.stops == 2)

        synth.cancel()
        await drain()
        #expect(synth.spoken == ["6", "4"])  // "5" was superseded before it ever spoke
    }

    /// Toggle-off mid-park: the parked result must not speak when the
    /// synth reports the cancel — `stop()` clears the slot too.
    @Test("stop clears a parked result")
    func stopClearsPending() async {
        let synth = MockSynthesizer()
        let speech = SpeechController(synthesizer: synth)

        speech.speak(RollResult(faces: [6]))
        speech.speak(RollResult(faces: [5]))
        speech.stop()
        #expect(synth.stops == 2)

        synth.cancel()
        await drain()
        #expect(synth.spoken == ["6"])
    }

    /// The delegate-hop gap: `didCancel` has fired on the synth's queue
    /// but the MainActor task hasn't run — `isSpeaking` already reads
    /// false while a result is still owed. A settle here must park, not
    /// speak ahead of it.
    @Test("a settle in the delegate gap still parks")
    func gapStillParks() async {
        let synth = MockSynthesizer()
        let speech = SpeechController(synthesizer: synth)

        speech.speak(RollResult(faces: [6]))
        speech.speak(RollResult(faces: [5]))   // parks "5"
        synth.cancel()                          // didCancel enqueued; hop pending
        #expect(!synth.isSpeaking)

        speech.speak(RollResult(faces: [4]))   // must park — "5" is still owed
        #expect(synth.spoken == ["6"])         // "4" did not start immediately
        #expect(synth.stops == 2)
        await drain()
        #expect(synth.spoken == ["6", "4"])
    }

    /// `didFinish` is the other half of the release path — a parked
    /// result must speak on natural completion too, not only on cancel.
    @Test("a natural finish also releases the parked result")
    func finishReleases() async {
        let synth = MockSynthesizer()
        let speech = SpeechController(synthesizer: synth)

        speech.speak(RollResult(faces: [6]))
        speech.speak(RollResult(faces: [5]))   // parks
        synth.finish()
        await drain()
        #expect(synth.spoken == ["6", "5"])
    }

    /// Barrier for the `Task { @MainActor }` hop inside the delegate
    /// callbacks: a no-op enqueued after it — MainActor is serial, so
    /// when this returns the hop has already run. Yields can't promise
    /// that; the stop test would pass without the callback ever firing.
    private func drain() async {
        await MainActor.run { }
    }
}

/// Stands in for `AVSpeechSynthesizer` without its timing: `speak` and
/// `stopSpeaking` record what the controller asked for, and the test
/// fires `finish()`/`cancel()` itself — the delegate callbacks are the
/// only part of the real synthesizer the controller reacts to.
@MainActor
private final class MockSynthesizer: AVSpeechSynthesizer {
    /// Backing for the `isSpeaking` override — can't be named `speaking`,
    /// which is the Objective-C property's own name.
    var isSpeakingNow = false
    override var isSpeaking: Bool { isSpeakingNow }
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    private var current: AVSpeechUtterance?

    override func speak(_ utterance: AVSpeechUtterance) {
        spoken.append(utterance.speechString)
        current = utterance
        isSpeakingNow = true
    }

    override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stops += 1
        isSpeakingNow = false
        // `current` survives: the real synth still reports the stopped
        // utterance through didCancel — that report is what the
        // controller's pending slot waits on.
        return true
    }

    func finish() {
        guard let utterance = current, let delegate else { return }
        isSpeakingNow = false
        current = nil
        // `?` — the delegate requirements are @optional, so the method
        // reference itself is optional.
        delegate.speechSynthesizer?(self, didFinish: utterance)
    }

    func cancel() {
        guard let utterance = current, let delegate else { return }
        isSpeakingNow = false
        current = nil
        delegate.speechSynthesizer?(self, didCancel: utterance)
    }
}
