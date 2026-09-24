import Foundation

/// Launch-argument switches for development and tuning runs, e.g.
/// `xcrun simctl launch … -autoroll -impulseLog`.
enum DevFlags {
    /// Throw a roll on appear — hands-free throw → settle → publish.
    static let autoroll = ProcessInfo.processInfo.arguments.contains("-autoroll")

    /// Log each roll's collision impulses and settle duration. Physics
    /// tuning and `HapticsController.maxImpulse` calibration should measure
    /// the real distribution instead of guessing constants.
    static let impulseLog = ProcessInfo.processInfo.arguments.contains("-impulseLog")
}
