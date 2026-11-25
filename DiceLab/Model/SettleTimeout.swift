import Foundation

/// Elapsed-time ceiling on a single roll before the table publishes anyway.
/// Engine-free UX guard, not physics tuning: each engine's own rest
/// signal can hold false forever — SceneKit's `isResting` never flips on
/// a die wedged against a wall, RealityKit's velocity thresholds keep
/// getting reset by micro-bounces — and either strands `isRolling` on
/// "Rolling…" (TD-5). The promise being guarded is "a throw always
/// ends," so the ceiling is seconds of elapsed monotonic time
/// (`systemUptime` at the call sites), identical on both engines.
///
/// 15 s at pace 1 is ~4–7× the slowest measured honest settle
/// (RealityKit ~2.2 s, SceneKit ~3.3–4.2 s at its 3× world speed): far
/// enough out that a wedged die can't be mistaken for a slow roll, near
/// enough that it lands well before a user assumes the app hung. The
/// ceiling scales by pace — honest settle wall-time is ~1/pace on both
/// engines, so a fixed ceiling would fire mid-roll at the slowest dial
/// settings. `-settleTimeout` shadows the result per-process for smoke
/// runs — see `DevFlags`.
enum SettleTimeout {
    static let seconds: TimeInterval = 15

    /// Floor for the pace `ceiling` divides by. The shipped dial bottoms
    /// at 0.25; below that only the unclamped `-pace` flag reaches, where
    /// the cap keeps the guard bounded (150 s) instead of dividing by zero
    /// or never firing.
    static let minPace: Double = 0.1

    /// The shipped ceiling at a playback rate. `-settleTimeout` bypasses
    /// this entirely — the override is absolute elapsed time.
    static func ceiling(pace: Double) -> TimeInterval {
        seconds / max(pace, minPace)
    }
}
