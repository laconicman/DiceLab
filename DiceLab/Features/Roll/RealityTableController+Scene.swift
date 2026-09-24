import RealityKit
import UIKit

/// World construction for the RealityKit table, mirroring
/// `DiceTableController+Scene.swift`. Two structural differences worth
/// noticing:
///
/// * The play volume is the SceneKit one **÷100** — RealityKit speaks meters
///   (a die is ~3 cm), and there is no `physicsWorld.speed` to tune, so the
///   roll plays at real-time gravity. Tuning numbers never port; structure
///   does.
/// * Invisible bounds need no `isHidden`: an entity without a
///   `ModelComponent` simply renders nothing. Physics is a component, not
///   a node type — the collision-only walls are entities with physics but
///   no model.
extension RealityTableController {

    func setUpScene() {
        setUpCamera()
        setUpLighting()
        setUpTable()
        spawnDice(dieCount)
    }

    private func setUpCamera() {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.01, far: 10, fieldOfViewInDegrees: 55))
        // ~45 cm above the felt, pulled slightly toward the viewer for the
        // same gentle tilt the SceneKit camera uses.
        camera.look(at: .zero, from: [0, 0.42, 0.03], relativeTo: nil)
        root.addChild(camera)
    }

    private func setUpLighting() {
        // Key light: the `DirectionalLight` entity type — the bare component
        // exposes no shadow on iOS, the entity does.
        let light = DirectionalLight()
        light.light.intensity = 2500
        light.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 1.0, depthBias: 4.0)
        light.look(at: .zero, from: [0.2, 1.0, 0.15], relativeTo: nil)
        root.addChild(light)

        // Fill: a dim point light above the table so shadow sides aren't
        // pitch black — iOS RealityKit has no ambient-light component.
        let fill = PointLight()
        fill.light.intensity = 500
        fill.light.attenuationRadius = 2
        fill.position = [0, 0.5, 0.3]
        root.addChild(fill)
    }

    /// The play volume in meters — SceneKit's `Bounds` ÷100.
    private enum Bounds {
        static let halfX: Float = 0.10     // x ∈ −0.10…0.10
        static let halfZ: Float = 0.15     // z ∈ −0.15…0.15
        static let floorY: Float = -0.08
        static let ceilingY: Float = 0.12
        static let thickness: Float = 0.04
        static let span: Float = 0.60
        static let dieEdge: Float = 0.03
        static let dieMass: Float = 0.02   // kg — impulse tuning assumes it
    }

    /// Friction/restitution pairs — named because they're the dials a device
    /// tuning pass would reach for first (TD-6).
    private enum PhysicsTune {
        static let tableFriction: Float = 0.6
        static let tableRestitution: Float = 0.3
        static let dieFriction: Float = 0.4
        static let dieRestitution: Float = 0.55
    }

    /// Physics material shared by table and dice — the SceneKit scene's
    /// implicit defaults made explicit: grippy felt, lively dice.
    private static let tableMaterial = PhysicsMaterialResource.generate(
        friction: PhysicsTune.tableFriction, restitution: PhysicsTune.tableRestitution)
    private static let dieMaterial = PhysicsMaterialResource.generate(
        friction: PhysicsTune.dieFriction, restitution: PhysicsTune.dieRestitution)

    private func setUpTable() {
        // Visible felt: a thin box whose top face sits on floorY. SCNFloor's
        // infinite plane has no direct RK analog; a box is honest geometry.
        let felt = Entity()
        var feltMaterial = PhysicallyBasedMaterial()
        feltMaterial.baseColor = .init(tint: UIColor(red: 0.05, green: 0.30,
                                                   blue: 0.15, alpha: 1))
        feltMaterial.roughness = 1.0
        let feltShape = ShapeResource.generateBox(
            size: [Bounds.span, Bounds.thickness, Bounds.span])
        felt.components.set(ModelComponent(
            mesh: .generateBox(size: [Bounds.span, Bounds.thickness, Bounds.span]),
            materials: [feltMaterial]))
        felt.components.set(CollisionComponent(shapes: [feltShape]))
        felt.components.set(PhysicsBodyComponent(
            shapes: [feltShape], density: 1,
            material: Self.tableMaterial, mode: .static))
        felt.position = [0, Bounds.floorY - Bounds.thickness / 2, 0]
        root.addChild(felt)

        // Walls + ceiling: collision-only entities — no ModelComponent, so
        // nothing renders. With per-body CCD on the dice, the 4-unit margin
        // the SceneKit walls needed shrinks to a formality.
        let wallY = (Bounds.floorY + Bounds.ceilingY) / 2
        func bound(_ size: SIMD3<Float>, at position: SIMD3<Float>) {
            let shape = ShapeResource.generateBox(size: size)
            let wall = Entity()
            wall.components.set(CollisionComponent(shapes: [shape]))
            wall.components.set(PhysicsBodyComponent(
                shapes: [shape], density: 1,
                material: Self.tableMaterial, mode: .static))
            wall.position = position
            root.addChild(wall)
        }

        bound([Bounds.span, Bounds.thickness, Bounds.span],
              at: [0, Bounds.ceilingY + Bounds.thickness / 2, 0])          // ceiling
        bound([Bounds.thickness, Bounds.span, Bounds.span],
              at: [Bounds.halfX + Bounds.thickness / 2, wallY, 0])         // +x
        bound([Bounds.thickness, Bounds.span, Bounds.span],
              at: [-Bounds.halfX - Bounds.thickness / 2, wallY, 0])        // −x
        bound([Bounds.span, Bounds.span, Bounds.thickness],
              at: [0, wallY, Bounds.halfZ + Bounds.thickness / 2])         // +z
        bound([Bounds.span, Bounds.span, Bounds.thickness],
              at: [0, wallY, -Bounds.halfZ - Bounds.thickness / 2])        // −z
    }

    /// Spawn geometry in meters — same spread rule as SceneKit, scaled ÷100.
    private enum Spawn {
        static let span: Float = 0.16
        static let maxSpacing: Float = 0.045
    }

    /// Spawn slots centered on the table midline. Static and pure so tests
    /// can pin the geometry — the mirror of the SceneKit version.
    static func spawnPositions(count: Int) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        let spacing = min(Spawn.maxSpacing, Spawn.span / Float(max(count - 1, 1)))
        let first = -spacing * Float(count - 1) / 2
        return (0..<count).map { SIMD3(first + spacing * Float($0), 0, 0) }
    }

    func spawnDice(_ count: Int) {
        for position in Self.spawnPositions(count: count) {
            let die = Self.makeDie(at: position, skin: skin)
            dice.append(die)
            root.addChild(die)
        }
    }

    /// Re-skins existing dice in place — materials are just a component
    /// property, so the swap is a straight reassignment.
    func applySkin() {
        let materials = Self.materials(skin: skin)
        for die in dice {
            die.components[ModelComponent.self]?.materials = materials
        }
    }

    /// The die mesh is shared across all dice — generated once, the same
    /// caching rule the SceneKit side applies to face images.
    static let dieMesh = MeshResource.generateBox(
        width: Bounds.dieEdge, height: Bounds.dieEdge, depth: Bounds.dieEdge,
        cornerRadius: Bounds.dieEdge * 0.06, splitFaces: true)

    private static func makeDie(at position: SIMD3<Float>, skin: DieSkin) -> ModelEntity {
        // `ModelEntity`, not bare `Entity`: the impulse methods
        // (`applyLinearImpulse`/`applyAngularImpulse`) hang off
        // `HasPhysicsBody`, which only the model-entity subclass conforms to.
        let die = ModelEntity(mesh: dieMesh, materials: materials(skin: skin))
        die.position = position

        let shape = ShapeResource.generateBox(
            size: .init(repeating: Bounds.dieEdge))
        var body = PhysicsBodyComponent(
            shapes: [shape], mass: Bounds.dieMass,
            material: dieMaterial, mode: .dynamic)
        // RealityKit exposes per-body continuous collision detection — the
        // exact API SceneKit withholds. The walls' thickness is still a
        // margin, but CCD is the guarantee the SceneKit scene can't buy.
        body.isContinuousCollisionDetectionEnabled = true
        die.components.set(body)
        die.components.set(CollisionComponent(shapes: [shape]))
        // Velocity lives on the motion component — added so `update` can
        // *read* rest, not just so impulses can write motion.
        die.components.set(PhysicsMotionComponent())
        return die
    }

    /// Six materials in the mesh's own part order — derived from geometry,
    /// never assumed (the M5 rule, kept). A split-faces box has one part per
    /// face; each part's bounding-box center *is* the face normal, quantized
    /// to the dominant axis via `DieFace.axes` — the same authority the
    /// reported face-up value uses.
    static func materials(skin: DieSkin) -> [any RealityKit.Material] {
        var slots: [any RealityKit.Material] = (0..<dieMesh.expectedMaterialCount)
            .map { _ in PhysicallyBasedMaterial() }
        for model in dieMesh.contents.models {
            for part in model.parts {
                guard part.materialIndex < slots.count else { continue }
                let axis = dominantAxis(of: centroid(of: part))
                slots[part.materialIndex] = faceMaterial(
                    DieFaceTexture.value(on: axis), skin: skin)
            }
        }
        return slots
    }

    private static func faceMaterial(_ value: Int,
                                     skin: DieSkin) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let image = DieFaceTexture.images(for: skin)[value - 1].cgImage,
           let texture = try? TextureResource.generate(
               from: image, options: .init(semantic: .color)) {
            material.baseColor = .init(tint: .white,
                                       texture: .init(texture))
        } else {
            // Texture generation shouldn't sink the die — fall back to the
            // skin's flat color; the die is still playable.
            material.baseColor = .init(tint: skin.faceColor)
        }
        material.roughness = 0.4
        return material
    }

    /// Mean position of a mesh part's vertices — for a split-faces box part,
    /// that's a point on the face, so its direction from the origin *is* the
    /// face normal. Same centroid trick as the SceneKit path's `meanVertex`.
    /// Internal so tests can pin the part→face mapping.
    static func centroid(of part: MeshResource.Part) -> SIMD3<Float> {
        var sum = SIMD3<Float>.zero
        var count = 0
        for position in part.positions {
            sum += position
            count += 1
        }
        return count == 0 ? .zero : sum / Float(count)
    }

    /// Dominant ±axis of a vector — same quantization as the SceneKit path.
    static func dominantAxis(of v: SIMD3<Float>) -> SIMD3<Float> {
        let absV = abs(v)
        if absV.x >= absV.y, absV.x >= absV.z { return SIMD3(sign(v.x), 0, 0) }
        if absV.y >= absV.z { return SIMD3(0, sign(v.y), 0) }
        return SIMD3(0, 0, sign(v.z))
    }

    private static func sign(_ x: Float) -> Float { x >= 0 ? 1 : -1 }
}
