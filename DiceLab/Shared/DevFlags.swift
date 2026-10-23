import Foundation

/// Launch-argument switches for development and tuning runs, e.g.
/// `xcrun simctl launch … -autoroll -impulseLog`.
///
/// Defaults caveat: `simctl spawn … defaults write <bundle> key` reaches
/// the app only for keys the app has never persisted — once `persist` has
/// written a key, the app's own value wins the merge. For an app-owned
/// key, `simctl uninstall` + reinstall resets enough state for an
/// external write to take.
enum DevFlags {
    /// Throw a roll on appear — hands-free throw → settle → publish.
    static let autoroll = ProcessInfo.processInfo.arguments.contains("-autoroll")

    /// Log each roll's collision impulses and settle duration. Physics
    /// tuning and `HapticsController.maxImpulse` calibration should measure
    /// the real distribution instead of guessing constants.
    static let impulseLog = ProcessInfo.processInfo.arguments.contains("-impulseLog")

    /// Open the appearance editor at launch — the live preview's layout and
    /// material response need visual QA on both engines, and `simctl` can't
    /// tap through the settings sheet to reach it.
    static let appearanceEditor =
        ProcessInfo.processInfo.arguments.contains("-appearanceeditor")

    /// Open the plain settings sheet at launch — the same drive-by as
    /// `appearanceEditor` but landing on the sections list (engine picker,
    /// dice count, dynamics), which is the storefront-capture scenario.
    static let settings =
        ProcessInfo.processInfo.arguments.contains("-settings")

    /// `-engine realityKit` — transient engine override for capture runs;
    /// the flag shadows the persisted `settings.engine` for the process
    /// lifetime and never writes it back (the `settings` flag pattern,
    /// not persistence), because `simctl spawn defaults write
    /// settings.engine` loses to the app's own persisted value — see the
    /// Defaults caveat above.
    static let engineOverride: DiceEngine? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-engine"),
              index + 1 < arguments.count
        else { return nil }
        return DiceEngine(rawValue: arguments[index + 1])
    }()

    /// Log dice that leave the play volume — the containment check the
    /// other flags can't see: an escaped die falls forever and never
    /// settles, which reads as a hang, not a leak. Escapes go to `os_log`
    /// (sim `log show`, Console.app on device) and stdout (`devicectl …
    /// --console`), since `print` alone doesn't reach `log show`.
    static let boundsProbe =
        ProcessInfo.processInfo.arguments.contains("-boundsProbe")

    /// Log the camera's elevation about its orbit pivot and the lowest
    /// height it has reached — the camera floor's evidence (M11) a
    /// screenshot can't carry; `-boundsProbe` for the camera.
    static let cameraLog =
        ProcessInfo.processInfo.arguments.contains("-cameraLog")

    /// `-pace 0.5` — transient pace override for timing runs; shadows the
    /// stored setting without writing it back. Deliberately unclamped:
    /// pushing past `RollDynamics.paceRange` is how the wall-thickness and
    /// settle margins get stress-tested. Pair with `-autoroll
    /// -impulseLog` to compare settle durations across paces.
    static let paceOverride: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-pace"),
              index + 1 < arguments.count
        else { return nil }
        return Double(arguments[index + 1])
    }()
}
