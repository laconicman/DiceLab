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

    /// `-settleTimeout 2` — transient settle-ceiling override for smoke
    /// runs; shadows the pace-scaled `SettleTimeout` ceiling absolutely
    /// for the process lifetime without writing anything back (the
    /// `-pace` pattern). Clamped at 0: a negative says nothing 0 doesn't
    /// — "publish on the next frame," which is how the timeout gets
    /// verified while dice still move. Pair with `-autoroll`.
    static let settleTimeoutOverride: TimeInterval? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-settleTimeout"),
              index + 1 < arguments.count,
              let value = Double(arguments[index + 1])
        else { return nil }
        return max(0, value)
    }()

    /// `-orbit 30` — park the camera at this elevation (degrees, clamped
    /// to the orbit band) about the fitted cluster every time the fit
    /// latches. A straight-down camera hides a floor reflection under the
    /// die that casts it, so reflection captures need the oblique view a
    /// finger would give — and `simctl` has no finger.
    static let orbitElevation: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-orbit"),
              index + 1 < arguments.count
        else { return nil }
        return Double(arguments[index + 1])
    }()

    /// `-translucency 0.6` — transient translucency override for glass-
    /// dice captures; shadows the stored dial without writing it back
    /// (the `-pace` pattern). Clamped to the dial's 0…1 — out-of-range
    /// values have no meaning to stress-test here.
    static let translucencyOverride: Double? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-translucency"),
              index + 1 < arguments.count,
              let value = Double(arguments[index + 1])
        else { return nil }
        return min(max(value, 0), 1)
    }()

    /// `-speechLog` — trace `SpeechController`'s park/release lifecycle
    /// to stdout (`devicectl … --console`). The simulator can't verify
    /// audible speech, so device runs are where the delegate path earns
    /// its evidence — this is the probe for TD-16-class bugs. The same
    /// flag also traces the roll pipeline (`throw`/`publish`/`onChange`)
    /// via `devTrace`, so a silent settle shows which link broke.
    static let speechLog = ProcessInfo.processInfo.arguments.contains("-speechLog")
}

/// Shared probe writer for `-speechLog` runs — one uptime-stamped format
/// across the publish/speak chain so device traces line up. Distinct
/// `[trace]` prefix from `SpeechController`'s `[speech]` lifecycle lines.
func devTrace(_ event: String) {
    guard DevFlags.speechLog else { return }
    print("[trace] \(String(format: "%.2f", ProcessInfo.processInfo.systemUptime)) \(event)")
}

extension DieAppearance {
    /// The die skin material builders should see: `-translucency`
    /// shadows the stored dial for the process lifetime — transient
    /// like `-pace`, never written back to the persisted theme.
    var effective: DieAppearance {
        guard let override = DevFlags.translucencyOverride else { return self }
        var copy = self
        copy.translucency = override
        return copy
    }
}
