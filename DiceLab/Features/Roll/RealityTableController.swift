import Foundation
import Observation
import RealityKit
import SwiftUI

/// RealityKit implementation of the `DiceTable` contract — M7's counterpart
/// to `DiceTableController`. The ownership story inverts: SceneKit lets the
/// controller own the whole `SCNScene` (view renders it), while `RealityView`
/// owns the container and the controller owns an *entity graph* handed over
/// once in `populate`. Mutations stay imperative either way.
///
/// `@MainActor` on the whole class: RealityKit is main-actor by design
/// (`MeshResource` is `@MainActor` too), and unlike the SceneKit path there
/// is no render-thread delegate to defend against.
@MainActor
@Observable
final class RealityTableController: DiceTable {
    /// The entity graph — the ECS analog of the owned `SCNScene`.
    let root = Entity()

    /// True from a throw until the physics settle. `private(set)`: views
    /// observe, only the controller mutates.
    private(set) var isRolling = false

    /// The last settled throw's outcome — `nil` until the first roll rests.
    private(set) var lastRoll: RollResult?

    /// Settled rolls, oldest first, capped — cleared when the dice set
    /// changes, same contract as the SceneKit controller.
    private(set) var history: [RollResult] = []

    /// Bumped per throw; queued settle checks compare against it so a re-roll
    /// can't be completed by the previous roll's in-flight frame callback.
    private var rollID = 0

    /// Consecutive frames every die stayed under the rest thresholds —
    /// RealityKit exposes velocities but no `isResting`, so "settled" is a
    /// definition we hold, not a flag we read.
    private var steadyFrames = 0

    /// Collision feel — `maxImpulse` rescales for meters: impulses are
    /// mass×velocity, and 20-gram dice move at m/s where SceneKit's mass-1
    /// dice move at tens of units/s.
    private let haptics = HapticsController(maxImpulse: 0.3)

    /// Dice currently on the table — `ModelEntity` because the impulse
    /// methods live on `HasPhysicsBody`, which bare `Entity` lacks.
    /// Internal so the `+Scene` extension can populate it during construction.
    var dice: [ModelEntity] = []

    /// Event subscriptions returned by `RealityViewContent.subscribe` —
    /// dropping them would unsubscribe, so they're retained here for the
    /// controller's lifetime.
    private var subscriptions: [EventSubscription] = []

    // MARK: Settings — the keys are shared with the SceneKit controller via
    // `TableSettings`: a setting is the user's choice about the *table*, not
    // the engine — switching engines must not reset dice count or skin.

    /// 1…6 dice on the table. Respawns the dice when changed.
    var dieCount = TableSettings.storedDieCount() {
        didSet {
            UserDefaults.standard.set(dieCount, forKey: TableSettings.dieCount)
            guard dieCount != oldValue else { return }
            respawnDice()
        }
    }

    var cameraControlEnabled = UserDefaults.standard.object(forKey: TableSettings.cameraControl) as? Bool ?? true {
        didSet { UserDefaults.standard.set(cameraControlEnabled, forKey: TableSettings.cameraControl) }
    }

    var hapticsEnabled = UserDefaults.standard.object(forKey: TableSettings.haptics) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: TableSettings.haptics)
            haptics.isEnabled = hapticsEnabled
        }
    }

    var skin = DieSkin(rawValue: UserDefaults.standard.string(forKey: TableSettings.skin) ?? "") ?? .ivory {
        didSet {
            UserDefaults.standard.set(skin.rawValue, forKey: TableSettings.skin)
            guard skin != oldValue else { return }
            applySkin()
        }
    }

    init() {
        haptics.isEnabled = hapticsEnabled
        setUpScene()
    }

    /// Called once from `RealityView`'s content closure: hands the graph over
    /// and wires the two scene events the controller cares about — collisions
    /// (feel) and per-frame updates (settle detection).
    func populate(_ content: inout RealityViewCameraContent) {
        // `.virtual` — render through our `PerspectiveCameraComponent` entity,
        // not the device camera (the world-tracking default would need AR).
        content.camera = .virtual
        // A return to this engine runs populate again on a fresh content —
        // drop the old view's subscriptions or they accumulate for the
        // controller's lifetime.
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        content.add(root)
        subscriptions.append(content.subscribe(to: CollisionEvents.Began.self) { [haptics] event in
            // Same rule as the SceneKit path: read the impulse, hop to main.
            Task { @MainActor in haptics.collision(impulse: event.impulse) }
        })
        subscriptions.append(content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            let generation = self?.rollID ?? 0
            Task { @MainActor in self?.update(generation: generation) }
        })
    }

    /// Called from the view when `scenePhase` becomes `.active` — also
    /// reloads settings the other engine may have written while inactive.
    func sceneActivated() {
        haptics.start()
        reloadSettings()
    }

    /// Dice-count changes rebuild the dice — cheaper than diffing per-entity
    /// add/remove for at most six entities.
    private func respawnDice() {
        for die in dice { die.removeFromParent() }
        dice = []
        rollID += 1 // a settle queued for the old dice must not publish
        isRolling = false
        lastRoll = nil
        history = []
        spawnDice(dieCount)
    }

    /// Throws every die: randomized linear + angular impulse, mirroring the
    /// SceneKit throw. Magnitudes are re-tuned for meters — the numbers do
    /// not port between engines, the *shape* of the code does.
    func roll() {
        rollID += 1
        steadyFrames = 0
        isRolling = true
        for die in dice {
            // Clear momentum first: a re-throw is a fresh throw, not a
            // compounding of whatever the die was doing.
            if var motion = die.components[PhysicsMotionComponent.self] {
                motion.linearVelocity = .zero
                motion.angularVelocity = .zero
                die.components.set(motion)
            }
            die.applyLinearImpulse(Self.randomLinearImpulse(), relativeTo: nil)
            die.applyAngularImpulse(Self.randomAngularImpulse(), relativeTo: nil)
        }
    }

    /// Rest definition, because RealityKit has no `isResting`: every die's
    /// linear and angular velocity below threshold, sustained `requiredFrames`
    /// consecutive updates. `SceneEvents.Update` already ticks on main; the
    /// generation guard rejects callbacks queued before a re-roll.
    private func update(generation: Int) {
        guard isRolling, rollID == generation else { return }
        let settled = dice.allSatisfy { die in
            guard let motion = die.components[PhysicsMotionComponent.self] else { return false }
            return simd_length(motion.linearVelocity) < Rest.linear
                && simd_length(motion.angularVelocity) < Rest.angular
        }
        steadyFrames = settled ? steadyFrames + 1 : 0
        guard steadyFrames >= Rest.requiredFrames else { return }
        steadyFrames = 0
        let result = RollResult(faces: dice.map { DieFace.up(of: $0.orientation) })
        lastRoll = result
        history.append(result)
        if history.count > 20 { history.removeFirst() }
        isRolling = false
    }

    /// Velocity magnitudes under which a die counts as still — tuned for
    /// meter-scale physics: 2 cm/s and a third of a radian per second.
    private enum Rest {
        static let linear: Float = 0.02
        static let angular: Float = 0.3
        /// ~¼ s at 60 fps: a die rocking on a corner can dip under threshold
        /// for a frame or two; settling must be *sustained*.
        static let requiredFrames = 15
    }

    /// Impulse magnitudes for a ~20 g die: J = m·v, so 0.03–0.05 N·s upward
    /// is a 1.5–2.5 m/s toss — dice clear the table by a few body lengths.
    private enum Toss {
        static let up: ClosedRange<Float> = 0.03...0.05
        static let lateral: ClosedRange<Float> = -0.012...0.012
        static let torque: ClosedRange<Float> = -0.0006...0.0006
    }

    private static func randomLinearImpulse() -> SIMD3<Float> {
        SIMD3(.random(in: Toss.lateral), .random(in: Toss.up), .random(in: Toss.lateral))
    }

    private static func randomAngularImpulse() -> SIMD3<Float> {
        SIMD3(.random(in: Toss.torque), .random(in: Toss.torque), .random(in: Toss.torque))
    }
}
