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
        spawnDice(dieCount)
        setUpPreview()
        // Dice and felt already read the stored appearance at build —
        // the lighting rig is the one piece that waits for this pass.
        applyLighting(theme.appearance.lighting)
    }

    private func setUpCamera() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        // Top-down view onto the table: 20 units up, tilted straight down.
        camera.position = SCNVector3(x: 0, y: 20, z: 2)
        camera.rotation = SCNVector4(x: 1, y: 0, z: 0, w: -.pi / 2)
        scene.rootNode.addChildNode(camera)
    }

    /// Nodes the appearance pass reaches for by name — the alternative is
    /// stored refs on the main class, and a name is honest enough for three
    /// fixed nodes.
    private enum NodeName {
        static let felt = "felt"
        static let keyLight = "keyLight"
        static let fillLight = "fillLight"
    }

    private func setUpLighting() {
        // Key light: one point source casting soft shadows — shadowRadius
        // blurs the shadow map at lookup, cheaper than a shadow map upscale.
        let key = SCNNode()
        key.name = NodeName.keyLight
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.castsShadow = true
        key.light?.shadowRadius = 6
        key.light?.shadowColor = UIColor.black.withAlphaComponent(0.5)
        key.position = SCNVector3(x: 0, y: 20, z: 10)
        scene.rootNode.addChildNode(key)

        // Fill light: flat ambient so the shadow sides aren't pitch black.
        let fill = SCNNode()
        fill.name = NodeName.fillLight
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = UIColor(white: 0.35, alpha: 1)
        scene.rootNode.addChildNode(fill)

        scene.background.contents = UIColor.black
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
        felt.reflectivity = 0 // TD-4: FloorPass warning is harmless at 0
        let feltAppearance = theme.appearance.felt
        felt.firstMaterial?.diffuse.contents =
            (feltAppearance.usesImage ? FeltImageStore.load() : nil)
            ?? feltAppearance.color.uiColor
        felt.firstMaterial?.roughness.contents = NSNumber(1) // matte felt
        felt.firstMaterial?.specular.contents = UIColor.black
        let floor = SCNNode(geometry: felt)
        floor.name = NodeName.felt
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

    /// Internal (not private) so the main file's `respawnDice` can rebuild —
    /// scene construction lives here, roll-state bookkeeping lives there.
    func spawnDice(_ count: Int) {
        for position in Self.spawnPositions(count: count) {
            let die = Self.makeDie(at: position, appearance: theme.appearance.die)
            dice.append(die)
            scene.rootNode.addChildNode(die)
        }
    }

    /// Spawn geometry: dice spread across `span` units of table width,
    /// never farther apart than `maxSpacing` (sparse sets stay clustered).
    private enum Spawn {
        static let span: Float = 16
        static let maxSpacing: Float = 4.5
    }

    /// Spawn slots centered on the table midline, evenly spread across the
    /// play volume's width. Static and pure so tests can pin the geometry.
    static func spawnPositions(count: Int) -> [SCNVector3] {
        guard count > 0 else { return [] }
        let spacing = min(Spawn.maxSpacing, Spawn.span / Float(max(count - 1, 1)))
        let first = -spacing * Float(count - 1) / 2
        return (0..<count).map { SCNVector3(first + spacing * Float($0), 0, 0) }
    }

    /// Re-skins the whole table in place — dice, felt, and lighting preset.
    /// The derived material mapping makes the die swap a straight
    /// reassignment; felt and lights are found by name.
    func applyAppearance() {
        let appearance = theme.appearance
        for die in dice {
            guard let box = die.geometry as? SCNBox else { continue }
            box.materials = DieFaceTexture.materials(for: box, appearance: appearance.die)
        }
        if let previewDie, let box = previewDie.geometry as? SCNBox {
            box.materials = DieFaceTexture.materials(for: box, appearance: appearance.die)
        }
        if let floor = scene.rootNode.childNode(withName: NodeName.felt, recursively: false) {
            floor.geometry?.firstMaterial?.diffuse.contents =
                (appearance.felt.usesImage ? FeltImageStore.load() : nil)
                ?? appearance.felt.color.uiColor
        }
        applyLighting(appearance.lighting)
    }

    /// One mood per preset — the SceneKit mapping is omni intensity,
    /// shadow softness/darkness, and ambient fill level.
    private func applyLighting(_ preset: LightingPreset) {
        let key = scene.rootNode.childNode(withName: NodeName.keyLight, recursively: false)?.light
        let fill = scene.rootNode.childNode(withName: NodeName.fillLight, recursively: false)?.light
        switch preset {
        case .studio:
            key?.intensity = 1000
            key?.shadowRadius = 6
            key?.shadowColor = UIColor.black.withAlphaComponent(0.5)
            fill?.color = UIColor(white: 0.35, alpha: 1)
        case .soft:
            key?.intensity = 700
            key?.shadowRadius = 14
            key?.shadowColor = UIColor.black.withAlphaComponent(0.3)
            fill?.color = UIColor(white: 0.5, alpha: 1)
        case .dramatic:
            key?.intensity = 1400
            key?.shadowRadius = 2
            key?.shadowColor = UIColor.black.withAlphaComponent(0.75)
            fill?.color = UIColor(white: 0.15, alpha: 1)
        }
    }

    /// The appearance editor's live preview: one die, a camera, lights —
    /// and nothing else. Reuses `makeDie` minus its physics (a statue has
    /// no table to hit). The die spins on a mixed axis so every face reads.
    private func setUpPreview() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(x: 0, y: 2.4, z: 3.2)
        previewScene.rootNode.addChildNode(camera)
        camera.look(at: SCNVector3(x: 0, y: 0, z: 0))

        let die = Self.makeDie(at: SCNVector3(x: 0, y: 0, z: 0),
                               appearance: theme.appearance.die)
        die.physicsBody = nil
        die.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0.9, y: 1.6, z: 0, duration: 3)))
        previewScene.rootNode.addChildNode(die)
        previewDie = die

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.position = SCNVector3(x: 0, y: 6, z: 4)
        previewScene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = UIColor(white: 0.4, alpha: 1)
        previewScene.rootNode.addChildNode(fill)
    }

    private static func makeDie(at position: SCNVector3, appearance: DieAppearance) -> SCNNode {
        // Chamfered box: the rounded edge is what lets a die tumble instead of
        // sliding like a brick.
        let geometry = SCNBox(width: 3, height: 3, length: 3, chamferRadius: 0.1)
        // Pips are mapped to material slots by inspecting the box's own
        // geometry — never a hardcoded index order (see DieFaceTexture).
        geometry.materials = DieFaceTexture.materials(for: geometry, appearance: appearance)

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
