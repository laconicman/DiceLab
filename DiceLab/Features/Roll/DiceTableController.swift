import Observation
import SceneKit

/// Owns the dice table: the SceneKit scene, the dice on it, and the state the
/// physics world reports back. Views bind to this controller; they never touch
/// SceneKit themselves.
@Observable
final class DiceTableController: NSObject {
    /// The rendered world. A `let` reference owned here because a scene must
    /// outlive any view that displays it — view structs are ephemeral values,
    /// recreated on every render pass.
    let scene = SCNScene()

    /// True from a throw until the physics settle. `private(set)`: views
    /// observe, only the controller mutates.
    private(set) var isRolling = false

    /// The last settled throw's outcome — `nil` until the first roll rests.
    private(set) var lastRoll: RollResult?

    /// Settled rolls, oldest first, capped at 20 — a session record, not a
    /// log. Cleared when the dice set changes (a result from another
    /// configuration would be meaningless).
    private(set) var history: [RollResult] = []

    /// Bumped per throw; the settle task compares against it so a re-roll
    /// can't be completed by the previous roll's queued publish.
    private var rollID = 0

    /// Collision feel — owned here so views never hear about Core Haptics.
    private let haptics = HapticsController()

    /// Dice currently on the table. Internal so the `+Scene` extension can
    /// populate it during construction.
    var dice: [SCNNode] = []

    // MARK: Settings — controller state because they shape the scene;
    // persisted to UserDefaults so the table reopens the way it was left.

    /// 1…6 dice on the table. Respawns the dice when changed.
    var dieCount = DiceTableController.storedDieCount() {
        didSet {
            UserDefaults.standard.set(dieCount, forKey: Keys.dieCount)
            guard dieCount != oldValue else { return }
            respawnDice()
        }
    }

    /// Free camera orbiting for debugging — the product tradeoff from TD-3
    /// is resolved by exposing the choice instead of shipping it silently.
    var cameraControlEnabled = UserDefaults.standard.object(forKey: Keys.cameraControl) as? Bool ?? true {
        didSet { UserDefaults.standard.set(cameraControlEnabled, forKey: Keys.cameraControl) }
    }

    /// Gates the haptic/audio knock — the engine exists either way.
    var hapticsEnabled = UserDefaults.standard.object(forKey: Keys.haptics) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics)
            haptics.isEnabled = hapticsEnabled
        }
    }

    /// Dice skin — re-textures the dice in place when changed.
    var skin = DieSkin(rawValue: UserDefaults.standard.string(forKey: Keys.skin) ?? "") ?? .ivory {
        didSet {
            UserDefaults.standard.set(skin.rawValue, forKey: Keys.skin)
            guard skin != oldValue else { return }
            applySkin()
        }
    }

    private enum Keys {
        static let dieCount = "settings.dieCount"
        static let cameraControl = "settings.cameraControl"
        static let haptics = "settings.haptics"
        static let skin = "settings.skin"
    }

    /// UserDefaults returns 0 for a missing Int — distinguish "never set"
    /// (default 3) from a stored value, then clamp into the supported range.
    private static func storedDieCount() -> Int {
        let raw = UserDefaults.standard.integer(forKey: Keys.dieCount)
        return raw == 0 ? 3 : min(max(raw, 1), 6)
    }

    /// NSObject, because `SCNSceneRendererDelegate`/`SCNPhysicsContactDelegate`
    /// are `NSObjectProtocol`s — the price of the controller doubling as the
    /// renderer/physics delegate.
    override init() {
        super.init()
        haptics.isEnabled = hapticsEnabled
        setUpScene()
    }

    /// Called from the view when `scenePhase` becomes `.active` — the system
    /// suspends the haptic engine in the background and never resumes it.
    func sceneActivated() {
        haptics.start()
    }

    /// Dice-count changes rebuild the dice — cheaper than juggling per-node
    /// add/remove diffs for at most six nodes.
    private func respawnDice() {
        for die in dice { die.removeFromParentNode() }
        dice = []
        rollID += 1 // a settle queued for the old dice must not publish
        isRolling = false
        lastRoll = nil
        history = []
        spawnDice(dieCount)
    }

    /// Throws every die: a randomized torque impulse for spin plus an upward
    /// force impulse for the toss.
    ///
    /// The ancestors applied the same fixed torque `(1, 2, -1, 1)` and force
    /// `(1, 24, 2)` to every die — correlated, repeatable rolls. Randomizing
    /// per die is what makes consecutive rolls differ.
    func roll() {
        rollID += 1
        isRolling = true
        for die in dice {
            // Clear momentum first: a re-throw is a fresh throw, not a
            // compounding of whatever the die was doing — and bounding the
            // speed is what makes the 4-unit colliders' margin real.
            die.physicsBody?.velocity = SCNVector3Zero
            die.physicsBody?.angularVelocity = SCNVector4Zero
            die.physicsBody?.applyTorque(Self.randomTorque(), asImpulse: true)
            die.physicsBody?.applyForce(Self.randomForce(), asImpulse: true)
        }
    }

    /// Impulse magnitudes are tuned for `physicsWorld.speed = 3` — physics
    /// runs faster than real time, so impulses can be gentler than they look.
    private static func randomTorque() -> SCNVector4 {
        SCNVector4(
            x: .random(in: -4...4),
            y: .random(in: -4...4),
            z: .random(in: -4...4),
            w: .random(in: 1...4)
        )
    }

    private static func randomForce() -> SCNVector3 {
        SCNVector3(
            x: .random(in: -4...4),
            y: .random(in: 20...28),
            z: .random(in: -4...4)
        )
    }
}

extension DiceTableController: SCNSceneRendererDelegate {
    /// Per-frame hook: publishes the result once every die is asleep.
    /// `isResting` is SceneKit's own settle signal — the ancestors polled
    /// velocity magnitudes by hand; Bullet already tracks that.
    ///
    /// The callback isn't documented as main-thread, and SwiftUI reads the
    /// published state on main — so publishing hops to `MainActor`.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isRolling else { return }
        let generation = rollID
        Task { @MainActor in
            // Everything dice-related happens here, not on the render
            // thread: `respawnDice` mutates the array on main, so iterating
            // it there would race. Re-verify inside the hop: a re-roll or
            // respawn between capture and now must not publish stale faces
            // or clear the new roll's flag — the generation guard covers
            // invalidation, the isResting re-check covers an impulse that
            // landed after it.
            guard isRolling, rollID == generation,
                  dice.allSatisfy({ $0.physicsBody?.isResting ?? false }) else { return }
            let result = RollResult(faces: dice.map { DieFace.up(of: $0.presentation.simdOrientation) })
            lastRoll = result
            history.append(result)
            if history.count > 20 { history.removeFirst() }
            isRolling = false
        }
    }
}

extension DiceTableController: SCNPhysicsContactDelegate {
    /// Fires on SceneKit's physics queue, not main — the only thing done here
    /// is read the impulse and hop; all mutation happens on the main actor.
    /// (That's REVIEW.md's rule, kept.)
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let impulse = Float(contact.collisionImpulse)
        Task { @MainActor [haptics] in
            haptics.collision(impulse: impulse)
        }
    }
}
