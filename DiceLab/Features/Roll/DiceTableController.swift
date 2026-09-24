import Observation
import SceneKit

/// Owns the dice table: the SceneKit scene, the dice on it, and the state the
/// physics world reports back. Views bind to this controller; they never touch
/// SceneKit themselves.
@Observable
final class DiceTableController {
    /// The rendered world. A `let` reference owned here because a scene must
    /// outlive any view that displays it — view structs are ephemeral values,
    /// recreated on every render pass.
    let scene = SCNScene()

    /// True from a throw until the physics settle (M3 detects rest and
    /// publishes the result). `private(set)`: views observe, only the
    /// controller mutates.
    private(set) var isRolling = false

    /// Dice currently on the table. Internal so the `+Scene` extension can
    /// populate it during construction.
    var dice: [SCNNode] = []

    init() {
        setUpScene()
    }

    /// Throws every die: a randomized torque impulse for spin plus an upward
    /// force impulse for the toss.
    ///
    /// The ancestors applied the same fixed torque `(1, 2, -1, 1)` and force
    /// `(1, 24, 2)` to every die — correlated, repeatable rolls. Randomizing
    /// per die is what makes consecutive rolls differ.
    func roll() {
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
