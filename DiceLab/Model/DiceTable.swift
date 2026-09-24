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
    /// Gates the haptic/audio knock — the engine exists either way.
    var hapticsEnabled: Bool { get set }
    /// Dice skin.
    var skin: DieSkin { get set }
    /// Throws every die.
    func roll()
    /// Called when `scenePhase` becomes `.active` — restart suspended systems.
    func sceneActivated()
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
