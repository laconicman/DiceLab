import Foundation
import Testing
@testable import DiceLab

/// The shared `RollDynamics` dials land on different hardware per engine;
/// these pins keep the per-engine mappings honest — the neutral dial must
/// reproduce each engine's tuned feel exactly.
struct DynamicsMappingTests {

    /// `physicsWorld.speed` is playback rate only; pace 1 must reproduce
    /// the ancestors' 3× tuning, and the dial scales linearly around it.
    @Test("SceneKit pace is the 3× baseline scaled")
    func sceneKitPace() {
        #expect(DiceTableController.Dynamics.baselineSpeed
                * RollDynamics().pace == 3)
        #expect(DiceTableController.Dynamics.baselineSpeed
                * RollDynamics.paceRange.lowerBound == 1.5)
        #expect(DiceTableController.Dynamics.baselineSpeed
                * RollDynamics.paceRange.upperBound == 4.5)
    }

    /// Neutral viscosity must land on *exactly* the implicit Bullet
    /// defaults — a hair more damping and the baseline stops matching the
    /// feel old builds shipped.
    @Test("SceneKit viscosity 0 is the implicit 0.1 damping")
    func sceneKitViscosity() {
        let tune = DiceTableController.Dynamics.self
        #expect(tune.baselineDamping + tune.viscosityGain * 0 == 0.1)
        #expect(tune.baselineDamping + tune.viscosityGain * 1 == 0.35)
    }

    /// `PhysicsTune.linearDamping` doubles as the viscosity-0 baseline —
    /// `applyDynamics` reads it directly, so the pin covers both dial ends.
    /// RealityKit's pace dial is `rate = pace` on the timebase — identity,
    /// nothing to map — so its pin lives in the model tests.
    @Test("RealityKit viscosity rides the 0.05 baseline")
    func realityViscosity() {
        let tune = RealityTableController.PhysicsTune.self
        #expect(tune.linearDamping + tune.viscosityGain * 0 == 0.05)
        #expect(tune.angularDamping == tune.linearDamping)
        #expect(tune.linearDamping + tune.viscosityGain * 1 == 0.4)
    }
}
