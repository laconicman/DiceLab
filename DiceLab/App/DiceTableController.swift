import Observation
import SceneKit

/// Owns the dice table: the SceneKit scene plus the state the physics world
/// reports back. Views bind to this controller; they never touch SceneKit
/// themselves.
@Observable
final class DiceTableController {
    /// The rendered world. It's a `let` reference owned here because a scene
    /// must outlive any view that displays it — SwiftUI view structs are
    /// ephemeral values, recreated on every render pass.
    let scene = SCNScene()

    /// Drives the Roll button's appearance. `private(set)`: views observe,
    /// only the controller mutates.
    private(set) var isRolling = false

    init() {
        setUpCamera()
        setUpLighting()
    }

    private func setUpCamera() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        // Top-down view onto the table: 20 units up, tilted straight down.
        // Same framing as DiceRollDemo — tweak later to taste.
        camera.position = SCNVector3(x: 0, y: 20, z: 2)
        camera.rotation = SCNVector4(x: 1, y: 0, z: 0, w: -.pi / 2)
        scene.rootNode.addChildNode(camera)
    }

    private func setUpLighting() {
        // Key light: one point source casting shadows.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.castsShadow = true
        key.position = SCNVector3(x: 0, y: 20, z: 10)
        scene.rootNode.addChildNode(key)

        // Fill light: flat ambient so the shadow sides aren't pitch black.
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(fill)
    }

    /// M2 will apply torque + force impulses here. For now it exists to prove
    /// the view → controller → published-state loop works end to end.
    func roll() {
        isRolling = true
    }
}
