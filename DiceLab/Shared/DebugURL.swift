import Foundation
import SwiftUI

/// The `dicelab://` debug channel — the runtime twin of `DevFlags`'
/// launch arguments, for driving a device build without relaunching:
/// `xcrun devicectl device process openURL --device <udid>
/// dicelab://roll`. It was chosen over a Darwin-notification observer
/// because the URL carries parameters (`pace/0.5`) in the same breath
/// as the poke, and `openURL` reaches a running app exactly like the
/// notification would. Every command mirrors something the UI already
/// exposes — nothing here grants power the Settings sheet doesn't.
enum DebugURL {
    enum Command: Equatable {
        /// Throw every die on the effective engine's table.
        case roll
        /// Report engine, pace, and the settle ceiling to the console.
        case state
        /// Write the pace dial — the real setting, so `applyDynamics`
        /// retunes the live world exactly like the slider does.
        case pace(Double)
        /// Rewrite the transient settle ceiling for this process —
        /// `DevFlags.settleTimeoutOverride`, same floor as `-settleTimeout`.
        case settleTimeout(TimeInterval)
        /// Swap the renderer — the same `@AppStorage` the picker writes.
        case engine(DiceEngine)
    }

    static let scheme = "dicelab"

    /// `dicelab://roll`, `dicelab://state`, `dicelab://pace/0.5`,
    /// `dicelab://settleTimeout/2`, `dicelab://engine/sceneKit`.
    /// Anything else — wrong scheme, unknown verb, bad number — is nil:
    /// a mistyped debug URL must not throw. Verbs match case-insensitively
    /// (the host is lowercased); the argument keeps its case because
    /// `DiceEngine.rawValue` is camelCase.
    static func command(from url: URL) -> Command? {
        guard url.scheme == scheme,
              let verb = url.host?.lowercased() else { return nil }
        let argument = url.pathComponents.dropFirst().first
        switch verb {
        case "roll": return .roll
        case "state": return .state
        case "pace":
            // `Double("nan")` parses; isFinite keeps it out of the dial —
            // a NaN pace would persist and poison `ceiling(pace:)`.
            guard let argument, let value = Double(argument),
                  value.isFinite else { return nil }
            // The dial's own range: this writes the persisted setting,
            // so an absurd value would poison every later launch. The
            // unclamped escape stays `-pace` at launch.
            return .pace(min(max(value, RollDynamics.paceRange.lowerBound),
                             RollDynamics.paceRange.upperBound))
        case "settletimeout":
            guard let argument, let value = Double(argument),
                  value.isFinite else { return nil }
            return .settleTimeout(max(0, value))
        case "engine":
            guard let argument,
                  let match = DiceEngine.allCases.first(where: {
                      $0.rawValue.lowercased() == argument.lowercased()
                  })
            else { return nil }
            return .engine(match)
        default: return nil
        }
    }

    /// Runs a parsed command against the live tables. `engine` is the
    /// persisted choice — `DevFlags.engineOverride` still shadows it for
    /// the process, so the *effective* engine decides which table rolls
    /// and reports. `@MainActor` because `DiceTable` is.
    @MainActor
    static func perform(_ command: Command,
                        sceneKit: DiceTableController,
                        reality: RealityTableController,
                        engine: Binding<DiceEngine>) {
        let effective = DevFlags.engineOverride ?? engine.wrappedValue
        let table: DiceTable = effective == .sceneKit ? sceneKit : reality
        switch command {
        case .roll:
            table.roll()
        case .state:
            let pace = DevFlags.paceOverride ?? table.dynamics.pace
            let ceiling = DevFlags.settleTimeoutOverride
                ?? SettleTimeout.ceiling(pace: pace)
            print("[DiceLab] debug state — engine=\(effective.rawValue) "
                + "pace=\(pace) settleCeiling=\(ceiling)s "
                + "isRolling=\(table.isRolling)")
        case .pace(let value):
            // Both controllers share the persisted key; writing both
            // keeps the inactive one from rolling back on reactivation.
            sceneKit.dynamics.pace = value
            reality.dynamics.pace = value
        case .settleTimeout(let value):
            DevFlags.settleTimeoutOverride = value
        case .engine(let value):
            engine.wrappedValue = value
        }
    }
}
