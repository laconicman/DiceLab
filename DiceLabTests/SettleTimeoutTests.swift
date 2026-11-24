import Foundation
import Testing
@testable import DiceLab

/// The TD-5 ceiling is the one place a wall-clock guard meets the pace
/// dial — these pins keep the scaling honest: it must track ~1/pace so
/// slow motion can't trip it mid-roll, and stay bounded at absurd paces.
struct SettleTimeoutTests {
    @Test("ceiling is 15 s at pace 1 and scales by 1/pace")
    func ceilingScalesWithPace() {
        #expect(SettleTimeout.ceiling(pace: 1) == 15)
        #expect(SettleTimeout.ceiling(pace: 2) == 7.5)
        #expect(SettleTimeout.ceiling(pace: 0.5) == 30)
        #expect(SettleTimeout.ceiling(pace: 0.25) == 60)
    }

    /// Below `minPace` — reachable only through the unclamped `-pace`
    /// flag — the divisor floors out: the ceiling caps at 150 s and a
    /// zero or negative pace can't divide by zero or publish instantly.
    @Test("the pace floor bounds the ceiling at 150 s")
    func ceilingIsBounded() {
        for pace in [0.0, -1.0, SettleTimeout.minPace / 2] {
            #expect(abs(SettleTimeout.ceiling(pace: pace) - 150) < 0.001)
        }
    }
}
