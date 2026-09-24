import Foundation
import Observation
import SceneKit
import Synchronization

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
    /// can't be completed by the previous roll's queued publish. Behind a
    /// `Mutex` because two readers live off-main — the physics contact
    /// delegate and the renderer callback both run on the render thread.
    private let rollID = Mutex(0)

    /// Collision feel — owned here so views never hear about Core Haptics.
    /// `maxImpulse` 15 from `-impulseLog`: the estimate's observed ceiling
    /// is ~15 N·s, so the hardest felt-slam lands at full intensity.
    private let haptics = HapticsController(maxImpulse: 15)

    /// `-impulseLog` bookkeeping: impulses gathered during a roll, then
    /// summarized at settle — the data a `maxImpulse` recalibration needs.
    private var rollImpulses: [Float] = []
    private var rollStartedAt: Date?

    /// Dice currently on the table. Internal so the `+Scene` extension can
    /// populate it during construction.
    var dice: [SCNNode] = []

    // MARK: Settings — controller state because they shape the scene;
    // persisted to UserDefaults so the table reopens the way it was left.

    /// 1…6 dice on the table. Respawns the dice when changed.
    var dieCount = TableSettings.storedDieCount() {
        didSet {
            UserDefaults.standard.set(dieCount, forKey: TableSettings.dieCount)
            guard dieCount != oldValue else { return }
            respawnDice()
        }
    }

    /// Free camera orbiting for debugging — the product tradeoff from TD-3
    /// is resolved by exposing the choice instead of shipping it silently.
    var cameraControlEnabled = UserDefaults.standard.object(forKey: TableSettings.cameraControl) as? Bool ?? true {
        didSet { UserDefaults.standard.set(cameraControlEnabled, forKey: TableSettings.cameraControl) }
    }

    /// Gates haptic taps — the engine exists either way.
    var hapticsEnabled = UserDefaults.standard.object(forKey: TableSettings.haptics) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: TableSettings.haptics)
            haptics.isHapticsEnabled = hapticsEnabled
        }
    }

    /// Gates the synthesized collision knock — a separate user choice from
    /// haptics, and the only channel on hardware without a Taptic Engine.
    /// Defaults from the legacy combined toggle via `storedSound()`.
    var soundEnabled = TableSettings.storedSound() {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: TableSettings.sound)
            haptics.isSoundEnabled = soundEnabled
        }
    }

    /// The table's look — preset theme or a custom appearance. Re-skins
    /// dice, felt, and lighting in place when changed.
    var theme = TableSettings.storedTheme() {
        didSet {
            TableSettings.persist(theme)
            guard theme != oldValue else { return }
            applyAppearance()
        }
    }

    /// NSObject, because `SCNSceneRendererDelegate`/`SCNPhysicsContactDelegate`
    /// are `NSObjectProtocol`s — the price of the controller doubling as the
    /// renderer/physics delegate.
    override init() {
        super.init()
        haptics.isHapticsEnabled = hapticsEnabled
        haptics.isSoundEnabled = soundEnabled
        setUpScene()
    }

    /// Called from the view when `scenePhase` becomes `.active` — the system
    /// suspends the haptic engine in the background and never resumes it.
    /// Also reloads settings: the other engine may have written the shared
    /// keys while this controller sat inactive.
    func sceneActivated() {
        haptics.start()
        reloadSettings()
    }

    /// Dice-count changes rebuild the dice — cheaper than juggling per-node
    /// add/remove diffs for at most six nodes.
    private func respawnDice() {
        for die in dice { die.removeFromParentNode() }
        dice = []
        _ = rollID.withLock { $0 += 1 } // a settle queued for the old dice must not publish
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
        _ = rollID.withLock { $0 += 1 }
        isRolling = true
        if DevFlags.impulseLog {
            rollImpulses = []
            rollStartedAt = Date()
        }
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

/// The shared table contract — every member already exists; conformance is
/// free because M1–M6 defined exactly this surface.
extension DiceTableController: DiceTable {}

extension DiceTableController: SCNSceneRendererDelegate {
    /// Per-frame hook: publishes the result once every die is asleep.
    /// `isResting` is SceneKit's own settle signal — the ancestors polled
    /// velocity magnitudes by hand; Bullet already tracks that.
    ///
    /// The callback isn't documented as main-thread, and SwiftUI reads the
    /// published state on main — so publishing hops to `MainActor`.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isRolling else { return }
        let generation = rollID.withLock { $0 }
        Task { @MainActor in
            // Everything dice-related happens here, not on the render
            // thread: `respawnDice` mutates the array on main, so iterating
            // it there would race. Re-verify inside the hop: a re-roll or
            // respawn between capture and now must not publish stale faces
            // or clear the new roll's flag — the generation guard covers
            // invalidation, the isResting re-check covers an impulse that
            // landed after it.
            guard isRolling, rollID.withLock({ $0 == generation }),
                  dice.allSatisfy({ $0.physicsBody?.isResting ?? false }) else { return }
            let result = RollResult(faces: dice.map { DieFace.up(of: $0.presentation.simdOrientation) })
            lastRoll = result
            history.append(result)
            if history.count > 20 { history.removeFirst() }
            isRolling = false
            if let started = rollStartedAt { logImpulseSummary(since: started) }
        }
    }

    /// The `-impulseLog` summary: one line per settled roll — enough to
    /// pick `maxImpulse` from the observed ceiling instead of guessing.
    private func logImpulseSummary(since start: Date) {
        let elapsed = Date().timeIntervalSince(start)
        let maxImpulse = rollImpulses.max() ?? 0
        let mean = rollImpulses.isEmpty ? 0 : rollImpulses.reduce(0, +) / Float(rollImpulses.count)
        print(String(format: "[DiceLab] settled %.2fs — %d contacts, impulse max %.3f mean %.3f N·s",
                     elapsed, rollImpulses.count, maxImpulse, mean))
    }
}

extension DiceTableController: SCNPhysicsContactDelegate {
    /// Closing speed → impulse estimate: mass-1 dice at ~0.5 restitution.
    private static let impulseScale: Float = 1.5


    /// Fires on SceneKit's physics queue, not main — the only thing done here
    /// is read the impulse and hop; all mutation happens on the main actor.
    /// (That's REVIEW.md's rule, kept.)
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        // `collisionImpulse` is deprecated and returns 0 on current SDKs —
        // measured via `-impulseLog`: 121 contacts, all 0.000. The impulse
        // is estimated instead as the closing speed along the contact
        // normal (the delegate fires inside the solver step, before the
        // response resolves, so velocities still read approach speeds) —
        // m·Δv, the same physics the deprecated property reported.
        let n = contact.contactNormal
        let a = contact.nodeA.physicsBody?.velocity ?? SCNVector3Zero
        let b = contact.nodeB.physicsBody?.velocity ?? SCNVector3Zero
        let closing = abs(Float(a.x - b.x) * Float(n.x)
                          + Float(a.y - b.y) * Float(n.y)
                          + Float(a.z - b.z) * Float(n.z))
        let impulse = closing * Self.impulseScale
        // Render-thread capture — `rollID` is a Mutex precisely because
        // this delegate and `roll()` don't share a thread.
        let generation = rollID.withLock { $0 }
        Task { @MainActor [haptics] in
            // Generation pins the sample to its roll — a contact queued
            // before settle but run after the next `roll()` would pass an
            // `isRolling`-only gate and contaminate the new stats.
            if DevFlags.impulseLog, isRolling,
               rollID.withLock({ $0 == generation }) {
                rollImpulses.append(impulse)
            }
            haptics.collision(impulse: impulse)
        }
    }
}
