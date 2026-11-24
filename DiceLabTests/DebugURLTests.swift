import Foundation
import Testing
@testable import DiceLab

/// The `dicelab://` parser is the only testable half of the debug
/// channel — dispatch needs live controllers. These pins keep a
/// mistyped URL inert (nil, never a throw) and the pace argument inside
/// the dial's range, since it writes the persisted setting.
struct DebugURLTests {
    private func command(_ string: String) -> DebugURL.Command? {
        DebugURL.command(from: URL(string: string)!)
    }

    @Test("verbs parse: roll, state")
    func verbs() {
        #expect(command("dicelab://roll") == .roll)
        #expect(command("dicelab://state") == .state)
        #expect(command("dicelab://ROLL") == .roll) // verb is case-insensitive
    }

    @Test("pace parses and clamps to the dial's range")
    func pace() {
        #expect(command("dicelab://pace/0.5") == .pace(0.5))
        #expect(command("dicelab://pace/99") == .pace(RollDynamics.paceRange.upperBound))
        #expect(command("dicelab://pace/-3") == .pace(RollDynamics.paceRange.lowerBound))
        #expect(command("dicelab://pace") == nil)
        #expect(command("dicelab://pace/fast") == nil)
    }

    @Test("settleTimeout parses with the flag's zero floor")
    func settleTimeout() {
        #expect(command("dicelab://settleTimeout/2") == .settleTimeout(2))
        #expect(command("dicelab://settleTimeout/-1") == .settleTimeout(0))
        #expect(command("dicelab://settleTimeout") == nil)
    }

    @Test("engine matches rawValue case-insensitively")
    func engine() {
        #expect(command("dicelab://engine/sceneKit") == .engine(.sceneKit))
        #expect(command("dicelab://engine/REALITYKIT") == .engine(.realityKit))
        #expect(command("dicelab://engine/physics") == nil)
        #expect(command("dicelab://engine") == nil)
    }

    @Test("wrong scheme, unknown verb, and junk are all nil")
    func rejects() {
        #expect(command("https://roll") == nil)
        #expect(command("dicelab://explode") == nil)
        #expect(command("dicelab://") == nil)
    }
}
