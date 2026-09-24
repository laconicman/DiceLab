import Foundation

/// The contract every dice-table implementation satisfies. Introduced by M7 so
/// the SwiftUI chrome can sit over either engine — SceneKit's scene graph or
/// RealityKit's ECS — without knowing which. Everything a view may observe or
/// a setting may toggle is spelled out here; everything engine-shaped stays
/// inside the concrete controllers.
protocol DiceTable: AnyObject, Observable {
    /// True from a throw until the physics settle.
    var isRolling: Bool { get }
    /// The last settled throw's outcome — `nil` until the first roll rests.
    var lastRoll: RollResult? { get }
    /// Settled rolls, oldest first, capped — cleared when the dice set changes.
    var history: [RollResult] { get }
    /// 1…6 dice on the table; respawns the dice when changed.
    var dieCount: Int { get set }
    /// Free camera orbiting, exposed to the user.
    var cameraControlEnabled: Bool { get set }
    /// Gates haptic taps — independent of sound since the two are
    /// separate user choices about feedback, not one feature.
    var hapticsEnabled: Bool { get set }
    /// Gates the synthesized collision knock — independent of haptics.
    var soundEnabled: Bool { get set }
    /// Dice skin.
    var skin: DieSkin { get set }
    /// Throws every die.
    func roll()
    /// Called when `scenePhase` becomes `.active` — restart suspended systems.
    func sceneActivated()
}

extension DiceTable {
    /// Re-reads the shared settings keys. The other engine may have written
    /// them while this controller sat inactive — controllers are constructed
    /// once at app start, so nothing else would refresh them. `didSet`
    /// guards make no-op writes cheap; only real changes respawn or re-skin.
    func reloadSettings() {
        let defaults = UserDefaults.standard
        dieCount = TableSettings.storedDieCount()
        cameraControlEnabled = defaults.object(forKey: TableSettings.cameraControl) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: TableSettings.haptics) as? Bool ?? true
        soundEnabled = TableSettings.storedSound()
        skin = DieSkin(rawValue: defaults.string(forKey: TableSettings.skin) ?? "") ?? .ivory
    }
}

/// UserDefaults keys, shared by both controllers and the app root — a setting
/// is the user's choice about the *table*, not the engine rendering it, so
/// both controllers must read and write the same slots.
enum TableSettings {
    static let dieCount = "settings.dieCount"
    static let cameraControl = "settings.cameraControl"
    static let haptics = "settings.haptics"
    static let sound = "settings.sound"
    static let skin = "settings.skin"
    static let engine = "settings.engine"

    /// UserDefaults returns 0 for a missing Int — distinguish "never set"
    /// (default 3) from a stored value, then clamp into the supported range.
    static func storedDieCount() -> Int {
        let raw = UserDefaults.standard.integer(forKey: dieCount)
        return raw == 0 ? 3 : min(max(raw, 1), 6)
    }

    /// Sound predates its own toggle: users who muted the old combined
    /// "Haptics & sound" switch expect silence to carry forward, so the
    /// haptics key is the honest default until `sound` has been written.
    static func storedSound(defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: sound) as? Bool { return stored }
        return defaults.object(forKey: haptics) as? Bool ?? true
    }
}

/// Which renderer drives the table. App-level state, not controller state:
/// the engine decides which controller instance exists at all.
enum DiceEngine: String, CaseIterable, Identifiable {
    case sceneKit
    case realityKit

    var id: Self { self }

    var title: String {
        switch self {
        case .sceneKit: "SceneKit"
        case .realityKit: "RealityKit"
        }
    }
}
