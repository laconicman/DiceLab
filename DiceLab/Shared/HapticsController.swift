import CoreHaptics

/// Collision-driven haptics and audio, after Apple's HapticBounce sample:
/// contact impulse → normalized intensity → one transient haptic + one
/// synthesized knock per impact, played together by the same engine.
///
/// Two wins over the ancestors' approach: `collisionImpulse` is the physically
/// meaningful quantity (they approximated with `penetrationDistance`), and
/// `CHHapticEngine` synthesizes the audio itself — no undocumented
/// `AudioServicesPlaySystemSound(1103)` IDs.
final class HapticsController {
    private var engine: CHHapticEngine?
    /// nil = nothing played yet; otherwise the last tap's timestamp.
    private var lastPlay: ContinuousClock.Instant?

    /// Empirical ceiling for a mass-1 die hitting the table at full impulse —
    /// impulses above it clamp to intensity 1.0 (HapticBounce's `kMaxVelocity`
    /// role). Tune by feel on device.
    static let maxImpulse: Float = 25

    /// A tumbling die contacts far more often than the Taptic Engine can
    /// render; 60 ms between taps keeps haptics readable.
    static let minInterval: Duration = .milliseconds(60)

    /// Below this intensity a contact isn't worth a tap — floor texture,
    /// not an event.
    static let intensityFloor: Float = 0.15

    init() {
        // No engine on devices without a haptic interface (simulator, iPad) —
        // `collision` then no-ops; callers don't need to care.
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // The server can drop the engine on route changes (calls, headphones);
        // restart it rather than losing haptics for the session.
        engine?.resetHandler = { [weak self] in
            try? self?.engine?.start()
        }
    }

    /// Starts (or restarts) the engine. The system suspends it when the app
    /// backgrounds and never resumes it — call on `scenePhase == .active`.
    /// `start()` is documented to block briefly, so it hops off the caller's
    /// thread.
    func start() {
        Task.detached { [engine] in try? engine?.start() }
    }

    /// One contact → at most one tap. Called on the main actor via the
    /// contact delegate's hop; `lastPlay` mutations stay serialized there.
    func collision(impulse: Float) {
        let intensity = Self.normalizedIntensity(for: impulse)
        guard intensity > Self.intensityFloor else { return }
        let now = ContinuousClock.now
        if let lastPlay, now - lastPlay < Self.minInterval { return }
        lastPlay = now

        let haptic = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                .init(parameterID: .hapticIntensity, value: intensity),
                // Sharper for harder hits, but never softer than a tap.
                .init(parameterID: .hapticSharpness, value: 0.3 + intensity * 0.5),
            ],
            relativeTime: 0)
        let knock = CHHapticEvent(
            eventType: .audioContinuous,
            parameters: [
                .init(parameterID: .audioVolume, value: intensity * 0.4),
                .init(parameterID: .audioPitch, value: -0.2),
                .init(parameterID: .decayTime, value: intensity * 0.15),
                .init(parameterID: .sustained, value: 0),
            ],
            relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [haptic, knock],
                                                 parameters: []),
              let player = try? engine?.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }

    /// Newton-seconds → 0…1. Extracted as pure math so tests can pin the
    /// clamp without a haptic engine.
    static func normalizedIntensity(for impulse: Float) -> Float {
        min(max(impulse / maxImpulse, 0), 1)
    }
}
