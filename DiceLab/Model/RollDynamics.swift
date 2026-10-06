import Foundation

/// How a throw feels, split from `Appearance` (how the table looks). Two
/// user-facing axes, both normalized so the model carries no engine
/// constants — each controller maps them onto its own physics API
/// (SceneKit `physicsWorld.speed` + Bullet damping vs RealityKit's
/// `PhysicsSimulationComponent.clock` + `linearDamping`). The derivation
/// lives in the research notes on issues #25/#26.
///
/// The axes are orthogonal by construction:
/// * `pace` scales *simulated* time — a pure playback dial. Damping,
///   gravity, and deactivation all live in sim-space, so a faster pace is
///   the same throw played sooner, not a different throw.
/// * `viscosity` bleeds motion in sim-space too — it changes the
///   trajectory, not the playback rate. If it were normalized to wall
///   time instead, moving the pace slider would silently retune the
///   physics, and the axes would stop being independent.
struct RollDynamics: Codable, Equatable, Hashable {
    /// Playback rate of the simulated world: 1.0 is the tuned baseline.
    var pace = 1.0
    /// Drag dial: 0 is the tuned baseline, 1 bleeds hard, 2 is molasses.
    var viscosity = 0.0

    /// Widened after TestFlight testers asked for more headroom on both
    /// dials. Extending the *axis* rather than the gain keeps a stored
    /// 1.0 meaning what it always did — baseline semantics don't move.
    static let paceRange: ClosedRange<Double> = 0.25...2
    static let viscosityRange: ClosedRange<Double> = 0...2

    init(pace: Double = 1.0, viscosity: Double = 0.0) {
        self.pace = pace
        self.viscosity = viscosity
    }

    /// Lenient decode, clamped — a partial or hand-edited payload lands on
    /// the baseline instead of failing the whole setting (same rule as the
    /// `Appearance` family). Out-of-range values clamp rather than bounce:
    /// a stored 99 should read as "max", not "reset".
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPace = try container.decodeIfPresent(Double.self, forKey: .pace) ?? 1.0
        let rawViscosity = try container.decodeIfPresent(Double.self, forKey: .viscosity) ?? 0
        pace = min(max(rawPace, Self.paceRange.lowerBound), Self.paceRange.upperBound)
        viscosity = min(max(rawViscosity, Self.viscosityRange.lowerBound),
                        Self.viscosityRange.upperBound)
    }
}
