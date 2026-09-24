import SceneKit

/// Scene construction, kept out of the main file: how the table is built
/// changes with milestones, what the controller exposes should not.
extension DiceTableController {

    func setUpScene() {
        // Ancestors' tuning: physics at 3× real time reads as a snappier roll.
        // Halved timestep because SceneKit exposes no per-body continuous
        // collision detection (Bullet has it, the API doesn't surface it) —
        // sub-stepping is the mitigation for fast dice tunneling.
        scene.physicsWorld.speed = 3
        scene.physicsWorld.timeStep = 1.0 / 120.0
        // Contact callbacks → haptics (M4). Only the dice opted into
        // contactTestBitMask, so every reported contact involves a die.
        scene.physicsWorld.contactDelegate = self
        setUpCamera()
        setUpLighting()
        setUpTable()
        spawnDice(3)
    }

    private func setUpCamera() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        // Top-down view onto the table: 20 units up, tilted straight down.
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

    /// The box the dice play in: floor, four walls, ceiling. The table is a
    /// *static* body — immovable geometry, cheaper than the ancestors'
    /// kinematic choice (kinematic is for objects moved by code).
    /// Inner faces of the play volume, plus collider dimensions. `Float`
    /// because `SCNVector3` fields are — geometry inits want `CGFloat`.
    private enum Bounds {
        static let halfX: Float = 10     // x ∈ −10…10
        static let halfZ: Float = 15     // z ∈ −15…15
        static let floorY: Float = -8
        static let ceilingY: Float = 12
        static let thickness: Float = 4
        static let span: Float = 60
    }

    private func setUpTable() {
        let felt = SCNFloor()
        felt.reflectivity = 0 // M5 decides between this and the grain texture
        felt.firstMaterial?.diffuse.contents = UIColor.systemGreen
        let floor = SCNNode(geometry: felt)
        floor.position.y = Bounds.floorY
        floor.physicsBody = .tableBody()
        scene.rootNode.addChildNode(floor)

        // Thin boxes, not the ancestors' oriented planes: an axis-aligned box
        // needs no orientation math at all — `reposition`'s arbitrary-normal
        // matrix dance earns nothing here. But a box collider is *finite*, so
        // thickness matters: a die takes ~24 units/s of impulse (mass 1.0,
        // measured), and a solver step can carry it ~1 unit — 4 units of
        // thickness is a margin, not a guarantee. What bounds the speed is
        // `roll()` clearing velocity before each impulse.
        let wallMaterial = SCNMaterial()
        wallMaterial.diffuse.contents = UIColor.systemGray.withAlphaComponent(0.15)

        func bound(_ size: SCNVector3, at position: SCNVector3, hidden: Bool = false) {
            let node = SCNNode(geometry: SCNBox(
                width: CGFloat(size.x), height: CGFloat(size.y),
                length: CGFloat(size.z), chamferRadius: 0))
            node.geometry?.materials = [wallMaterial]
            node.position = position
            node.isHidden = hidden
            node.physicsBody = .tableBody()
            scene.rootNode.addChildNode(node)
        }

        // Each center sits half a thickness outside its inner face, so the
        // faces land exactly on the declared volume — and the spans pad past
        // the corners and the ceiling's top face.
        let wallY = (Bounds.floorY + Bounds.ceilingY) / 2
        bound(SCNVector3(Bounds.span, Bounds.thickness, Bounds.span),
              at: SCNVector3(0, Bounds.ceilingY + Bounds.thickness / 2, 0),
              hidden: true)                                                    // ceiling
        bound(SCNVector3(Bounds.thickness, Bounds.span, Bounds.span),
              at: SCNVector3(Bounds.halfX + Bounds.thickness / 2, wallY, 0))  // +x wall
        bound(SCNVector3(Bounds.thickness, Bounds.span, Bounds.span),
              at: SCNVector3(-Bounds.halfX - Bounds.thickness / 2, wallY, 0)) // −x wall
        bound(SCNVector3(Bounds.span, Bounds.span, Bounds.thickness),
              at: SCNVector3(0, wallY, Bounds.halfZ + Bounds.thickness / 2))  // +z wall
        bound(SCNVector3(Bounds.span, Bounds.span, Bounds.thickness),
              at: SCNVector3(0, wallY, -Bounds.halfZ - Bounds.thickness / 2)) // −z wall
    }

    private func spawnDice(_ count: Int) {
        let positions: [SCNVector3] = [
            SCNVector3(-4, 0, 0), SCNVector3(0, 0, 0), SCNVector3(4, 0, 0),
        ]
        for position in positions.prefix(count) {
            let die = Self.makeDie(at: position)
            dice.append(die)
            scene.rootNode.addChildNode(die)
        }
    }

    private static func makeDie(at position: SCNVector3) -> SCNNode {
        // Chamfered box: the rounded edge is what lets a die tumble instead of
        // sliding like a brick.
        let geometry = SCNBox(width: 3, height: 3, length: 3, chamferRadius: 0.1)
        geometry.firstMaterial?.diffuse.contents = UIColor.white

        let die = SCNNode(geometry: geometry)
        die.position = position
        die.castsShadow = true

        let body = SCNPhysicsBody(type: .dynamic, shape: nil)
        let diceAndTable = PhysicsCategory.die.union(.table).rawValue
        body.categoryBitMask = PhysicsCategory.die.rawValue
        body.collisionBitMask = diceAndTable
        // M4 reads contacts for haptics/audio; the dice opt in, the table's
        // `contactTestBitMask` stays 0 — one side opting in is enough.
        body.contactTestBitMask = diceAndTable
        die.physicsBody = body

        return die
    }
}

extension SCNPhysicsBody {
    /// Immovable table geometry: reports its category, collides with dice,
    /// reports no contacts itself — the dice opt in, the table doesn't have to.
    /// (Contact delivery is asymmetric: one side's `contactTestBitMask`
    /// matching the other's category is enough.)
    static func tableBody() -> SCNPhysicsBody {
        let body = SCNPhysicsBody(type: .static, shape: nil)
        body.categoryBitMask = PhysicsCategory.table.rawValue
        body.collisionBitMask = PhysicsCategory.die.rawValue
        return body
    }
}
