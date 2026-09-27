import Foundation
import Observation
import SceneKit
import Synchronization

/// Owns the dice table: the SceneKit scene, the dice on it, and the state the
/// physics world reports back. Views bind to this controller; they never touch
/// SceneKit themselves.
///
/// `@MainActor` — every mutation already ran there (roll, respawn, settle
/// publish); the annotation makes it real. The two delegate callbacks that
/// SceneKit fires on the render thread opt back out with `nonisolated` and
/// read nothing outside the `sync` Mutex before hopping.
@MainActor
@Observable
final class DiceTableController: NSObject {
    /// The rendered world. A `let` reference owned here because a scene must
    /// outlive any view that displays it — view structs are ephemeral values,
    /// recreated on every render pass.
    let scene = SCNScene()

    /// A one-die mini-scene for the appearance editor's live preview —
    /// separate world, re-materialized alongside the table by
    /// `applyAppearance`.
    let previewScene = SCNScene()

    /// The preview's die — `applyAppearance` re-materials it with the rest.
    /// Internal so `+Scene` can populate it during construction.
    var previewDie: SCNNode?

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
    /// `rolling` shares the lock: `isRolling` is the main-actor mirror the
    /// views observe, this is the value the render thread may read.
    private let sync = Mutex((rollID: 0, rolling: false))

    /// Collision feel — owned here so views never hear about Core Haptics.
    /// `maxImpulse` 15 from `-impulseLog`: the estimate's observed ceiling
    /// is ~15 N·s, so the hardest felt-slam lands at full intensity.
    private let haptics = HapticsController(maxImpulse: 15)

    /// `-impulseLog` bookkeeping: impulses gathered during a roll, then
    /// summarized at settle — the data a `maxImpulse` recalibration needs.
    private var rollImpulses: [Float] = []
    private var rollStartedAt: Date?

    /// The last backdrop `applyBackdrop` rendered — `applyAppearance`
    /// re-applies every channel on any edit, and a slider drag shouldn't
    /// redraw the equirect gradient per tick.
    var appliedBackdrop: BackdropAppearance?

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

    /// Scripted framing while a roll is in flight — see `updateCameraFit`
    /// in `+Scene`. Orbit controls stay attached regardless: the fit owns
    /// the camera while writing, and `fitConverged` hands it back once the
    /// settled pose arrives. Re-enabling clears the latch so a camera the
    /// user moved while fit was off pulls back to the fitted pose.
    var cameraFitEnabled = UserDefaults.standard.object(forKey: TableSettings.cameraFit) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(cameraFitEnabled, forKey: TableSettings.cameraFit)
            // Only a real off→on transition unlatches: `reloadSettings`
            // rewrites the unchanged value on every activation, and
            // clearing the latch then would steal the user's orbit.
            if cameraFitEnabled && !oldValue { fitConverged = false }
        }
    }

    /// Viewport aspect (width/height) fed by the view — the fit math needs
    /// it because horizontal FOV, not vertical, binds in portrait.
    var viewAspect: Double = 1

    /// The table camera — a stored ref rather than the name lookup the
    /// lights use, because the fit pass writes it every frame.
    /// Internal so `+Scene` populates it during construction.
    var cameraNode: SCNNode?

    /// `updateCameraFit`'s frame-to-frame delta source — `now` arrives as
    /// an absolute timestamp, the damp needs a delta.
    var lastFitTime: TimeInterval?

    /// Once the fitted pose has converged after a settle, the fit stops
    /// writing: orbit gestures are then free, with no per-frame
    /// tug-of-war, until the next `roll()` or dice respawn unlatches it.
    var fitConverged = false

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
        // A settle queued for the old dice must not publish.
        sync.withLock { $0.rollID += 1; $0.rolling = false }
        isRolling = false
        lastRoll = nil
        history = []
        fitConverged = false // refit to the fresh spawn cluster
        spawnDice(dieCount)
    }

    /// Throws every die: a randomized torque impulse for spin plus an upward
    /// force impulse for the toss.
    ///
    /// The ancestors applied the same fixed torque `(1, 2, -1, 1)` and force
    /// `(1, 24, 2)` to every die — correlated, repeatable rolls. Randomizing
    /// per die is what makes consecutive rolls differ.
    func roll() {
        sync.withLock { $0.rollID += 1; $0.rolling = true }
        isRolling = true
        fitConverged = false // a fresh throw re-owns the camera
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
/// free because M1–M6 defined exactly this surface and the class is already
/// main-actor.
extension DiceTableController: DiceTable {}

extension DiceTableController: SCNSceneRendererDelegate {
    /// Per-frame hook: publishes the result once every die is asleep.
    /// `isResting` is SceneKit's own settle signal — the ancestors polled
    /// velocity magnitudes by hand; Bullet already tracks that.
    ///
    /// The callback isn't documented as main-thread, and SwiftUI reads the
    /// published state on main — so publishing hops to `MainActor`.
    /// `nonisolated`: SceneKit calls this on the render thread. It reads
    /// only the `sync` Mutex — `rolling` lives there, never as the plain
    /// `isRolling` — then hops to main for everything dice-related.
    nonisolated func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor in
            // Everything dice-related happens here, not on the render
            // thread: `respawnDice` mutates the array on main, so iterating
            // it there would race. Re-verify inside the hop: a re-roll or
            // respawn between capture and now must not publish stale faces
            // or clear the new roll's flag — the generation guard covers
            // invalidation, the isResting re-check covers an impulse that
            // landed after it.
            if let generation = sync.withLock({ $0.rolling ? $0.rollID : nil }),
               isRolling, sync.withLock({ $0.rollID == generation }),
               dice.allSatisfy({ $0.physicsBody?.isResting ?? false }) {
                let result = RollResult(faces: dice.map { DieFace.up(of: $0.presentation.simdOrientation) })
                lastRoll = result
                history.append(result)
                if history.count > 20 { history.removeFirst() }
                isRolling = false
                sync.withLock { $0.rolling = false }
                if let started = rollStartedAt { logImpulseSummary(since: started) }
            }
            // The camera fit must keep easing *after* the rolling flag
            // clears — the settle publish above is what lands it — so it
            // can't sit behind a `rolling` early-out.
            updateCameraFit(now: time)
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

/// Closing speed → impulse estimate: mass-1 dice at ~0.5 restitution.
/// File-scoped, not a class member: `physicsWorld(didBegin:)` is
/// `nonisolated`, and a `static let` on a `@MainActor` class would be
/// actor-isolated where it doesn't need to be.
private enum ImpulseEstimate {
    static let scale: Float = 1.5
}

extension DiceTableController: SCNPhysicsContactDelegate {


    /// `nonisolated`: fires on SceneKit's physics queue, not main — the only
    /// thing done here is read the contact velocities and `sync`, then hop;
    /// all mutation happens on the main actor. (REVIEW.md's rule, kept.)
    nonisolated func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
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
        let impulse = closing * ImpulseEstimate.scale
        // Render-thread capture — `rollID` is inside the Mutex precisely
        // because this delegate and `roll()` don't share a thread.
        let generation = sync.withLock { $0.rollID }
        Task { @MainActor in
            // Generation pins the sample to its roll — a contact queued
            // before settle but run after the next `roll()` would pass an
            // `isRolling`-only gate and contaminate the new stats.
            // `haptics` reads here, not in a capture list: the property is
            // main-actor, so touching it at capture time would race.
            if DevFlags.impulseLog, isRolling,
               sync.withLock({ $0.rollID == generation }) {
                rollImpulses.append(impulse)
            }
            haptics.collision(impulse: impulse)
        }
    }
}
