import Foundation
import Testing
@testable import DiceLab

/// Pins for the `pace × viscosity` contract: the model stays normalized and
/// engine-free, and each engine's constants reproduce today's feel exactly
/// at the neutral dials — that's the whole point of "baseline at default".
struct RollDynamicsTests {

    @Test("defaults are the tuned baselines, not zeros")
    func defaults() {
        #expect(RollDynamics() == RollDynamics(pace: 1.0, viscosity: 0))
        // 0 is a valid viscosity (the baseline), so a missing payload must
        // not read as "fully dry" by accident — the two are the same here,
        // which is why the pin uses explicit values, not `== RollDynamics()`.
        #expect(RollDynamics.paceRange.contains(1.0))
        #expect(RollDynamics.viscosityRange.contains(0))
    }

    @Test("Codable round-trips a non-default pair")
    func roundTrip() throws {
        let dynamics = RollDynamics(pace: 1.25, viscosity: 0.4)
        let data = try JSONEncoder().encode(dynamics)
        #expect(try JSONDecoder().decode(RollDynamics.self, from: data) == dynamics)
    }

    /// A payload from before a key existed — or hand-edited — must land on
    /// the baseline rather than fail the decode, same rule as `Appearance`.
    @Test("missing keys decode leniently to the baseline")
    func lenientDecode() throws {
        #expect(try JSONDecoder().decode(RollDynamics.self, from: Data("{}".utf8))
                == RollDynamics())
        #expect(try JSONDecoder().decode(RollDynamics.self, from: Data(#"{"pace":0.75}"#.utf8))
                == RollDynamics(pace: 0.75))
    }

    /// Out-of-range clamps to the nearest supported dial, not a reset:
    /// a stored 99 means "max", not "baseline".
    @Test("out-of-range values clamp to the dial ends")
    func clamping() throws {
        #expect(try JSONDecoder().decode(
                    RollDynamics.self,
                    from: Data(#"{"pace":99,"viscosity":-4}"#.utf8))
                == RollDynamics(pace: RollDynamics.paceRange.upperBound,
                                viscosity: RollDynamics.viscosityRange.lowerBound))
    }
}
