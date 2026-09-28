import os
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
        applyLighting(theme.appearance.lighting, in: scene.rootNode)
        applyLighting(theme.appearance.lighting, in: previewScene.rootNode)
        applyBackdrop(theme.appearance.backdrop)
    }

    /// The camera's rest pose: 20 units up, tilted straight down, slightly
    /// viewer-ward in z. `axis` is the direction fitting slides along —
    /// straight up — so a fitted camera always looks directly at the
    /// cluster centroid without ever re-aiming (fixed orientation, no
    /// gimbal edge cases from `look(at:)` near vertical).
    private enum CameraHome {
        static let position = SIMD3<Float>(0, 20, 2)
        static let axis = SIMD3<Float>(0, 1, 0)
        /// Straight-down pose — the `rotation` vector at setup as a quat.
        /// Damped back toward on every fitted frame so an orbit the user
        /// took between rolls unwinds instead of lingering.
        static let orientation = simd_quaternion(-Float.pi / 2,
                                                 SIMD3<Float>(1, 0, 0))
    }

    /// Scripted-fit tuning (M9b). `speed` is the gate: above it dice are
    /// flying and the camera holds home; below it the camera fits. In
    /// SceneKit physics units — a fresh impulse is ~20 u/s, settle sits at
    /// ~0, so anything under a few units/s means "final tumbling."
    private enum Fit {
        static let speed: Float = 4
        /// Per-axis breathing room: a die's silhouette half-diagonal
        /// (~2.6 for the 3-unit box) plus ~2 units of visible felt, so
        /// the extreme die sits well inside the frame instead of flush
        /// against it.
        static let padding: Float = 4.5
        /// Never zoom closer than this — the floor keeps a compact
        /// cluster (or a lone die) from filling the screen; at this range
        /// a die is ~a quarter of the viewport width. The far cap isn't a
        /// constant: it's "the widest cluster the volume can hold,"
        /// computed per-frame. The box is centered on the cluster
        /// midpoint, and each axis's worst case is a die center pinned at
        /// that wall — half-extent + padding.
        static let minDistance: Float = 22
        static var volumeExtents: SIMD2<Float> {
            .init(Bounds.halfX + padding, Bounds.halfZ + padding)
        }
        /// Exponential damp rate: ~99% converged in one second, and tracks
        /// a moving target without animation restarts.
        static let rate: Float = 5
        /// Converged-pose epsilon — a fraction of a die's edge (3 units).
        static let epsilon: Float = 0.05
        /// A paused renderer resumes with the whole pause inside `dt`
        /// (damp ≈ 1 → snap). Capping at 100 ms keeps resumes gliding.
        static let maxDt: Float = 0.1
    }

    /// Per-frame camera framing, called from the renderer hop. The target
    /// flips between the home pose (dice flying, or nothing rolled yet)
    /// and the fitted pose (dice slow or settled — the "stay fitted" end
    /// state), and the damped position glides between them — the easing
    /// chain emerges from the target selection, no explicit animations.
    /// Once the fitted pose converges after a settle, `fitConverged`
    /// latches and the fit stops writing — the orbit gesture is then free
    /// instead of fighting a per-frame write.
    ///
    /// Returns whether the camera is still en route — the delegate uses
    /// it to keep the event-driven `SCNView` drawing until the glide
    /// lands (see the call site). `false` when the fit is off, latched,
    /// or the camera already sits on the current target.
    @discardableResult
    func updateCameraFit(now: TimeInterval) -> Bool {
        // dt bookkeeping runs unconditionally: early-returning on a
        // disabled fit would leave `lastFitTime` stale, and re-enabling
        // would then snap (huge dt → damp ≈ 1) instead of gliding.
        let dt = min(lastFitTime.map { Float(now - $0) } ?? 0, Fit.maxDt)
        lastFitTime = now
        guard cameraFitEnabled, !fitConverged,
              let camera = cameraNode else { return false }

        let positions = dice.map { $0.presentation.simdPosition }
        let fastest = dice.compactMap { die -> Float? in
            guard let v = die.physicsBody?.velocity else { return nil }
            return simd_length(simd_float3(v))
        }.max() ?? 0
        let box = CameraFit.boundingBox(of: positions, padding: Fit.padding)
        let fov = camera.camera?.fieldOfView ?? 60
        var distance = CameraFit.requiredDistance(
            xExtent: box.extents.x, zExtent: box.extents.y,
            verticalFieldOfView: Float(fov),
            aspect: Float(viewAspect))
        let maxDistance = CameraFit.requiredDistance(
            xExtent: Fit.volumeExtents.x, zExtent: Fit.volumeExtents.y,
            verticalFieldOfView: Float(fov),
            aspect: Float(viewAspect))
        distance = min(max(distance, Fit.minDistance), maxDistance)
        // Only reach for the cluster once the dice are nearly down; while
        // they fly (or before the first roll) the target is simply home.
        let fitting = !positions.isEmpty && (!isRolling || fastest < Fit.speed)
        let target = fitting
            ? box.center + CameraHome.axis * distance
            : CameraHome.position
        // A NaN transform blanks the frame *permanently* — the damp can't
        // recover because NaN + x = NaN. Snap back to sanity instead.
        if !camera.simdPosition.x.isFinite {
            camera.simdPosition = CameraHome.position
        }
        // Settled + arrived: snap the last fraction of a unit and hand the
        // camera back to the user. Only when not rolling — dice may still
        // drift while `isResting` hasn't flipped yet.
        if !isRolling, fitting,
           simd_distance(camera.simdPosition, target) < Fit.epsilon,
           abs(simd_dot(camera.simdOrientation, CameraHome.orientation)) > 0.9999 {
            camera.simdPosition = target
            camera.simdOrientation = CameraHome.orientation
            fitConverged = true
            return false
        }
        camera.simdPosition = CameraFit.damp(
            camera.simdPosition, toward: target, rate: Fit.rate, dt: dt)
        // Orientation is never the fit's knob — the axis is fixed — but
        // the user may have orbited between rolls; ease that back too.
        // `CameraFit.damp` guards the identical-quat NaN `simd_slerp` hits.
        camera.simdOrientation = CameraFit.damp(
            camera.simdOrientation, toward: CameraHome.orientation,
            rate: Fit.rate, dt: dt)
        return simd_distance(camera.simdPosition, target) > Fit.epsilon
            || abs(simd_dot(camera.simdOrientation, CameraHome.orientation)) <= 0.9999
    }

    private func setUpCamera() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        // The fit can retreat the camera ~150 units out in a narrow
        // viewport; the default zFar (100) would clip the dice itself.
        camera.camera?.zFar = 300
        // Top-down view onto the table: 20 units up, tilted straight down.
        camera.position = SCNVector3(CameraHome.position)
        camera.rotation = SCNVector4(x: 1, y: 0, z: 0, w: -.pi / 2)
        scene.rootNode.addChildNode(camera)
        cameraNode = camera
    }

    /// `-boundsProbe` diagnostics: flags the first position a die is seen
    /// outside the play volume (naming the face it crossed) and dumps rest
    /// positions at settle.
    private static let probeLog = Logger(subsystem: "DiceLab", category: "bounds")

    func probeBounds() {
        guard DevFlags.boundsProbe else { return }
        for (i, die) in dice.enumerated() {
            let p = die.presentation.simdPosition
            let out: String
            if p.y > Bounds.ceilingY { out = "ceiling" }
            else if p.y < Bounds.floorY { out = "floor" }
            else if abs(p.x) > Bounds.halfX { out = "x-wall" }
            else if abs(p.z) > Bounds.halfZ { out = "z-wall" }
            else { continue }
            if probeEscaped.insert("\(i)-\(out)").inserted {
                let m = "escape via \(out): die \(i) at \(p.x),\(p.y),\(p.z)"
                Self.probeLog.error("\(m)")
                print("[DiceLab] \(m)")
            }
        }
    }

    func probeRest() {
        guard DevFlags.boundsProbe else { return }
        for (i, die) in dice.enumerated() {
            let p = die.presentation.simdPosition
            Self.probeLog.notice("rest: die \(i) at \(p.x),\(p.y),\(p.z)")
            print("[DiceLab] rest: die \(i) at \(p.x),\(p.y),\(p.z)")
        }
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
        /// The felt's visible reach — far past the fitted camera's max
        /// retreat (`Fit.volumeRadius` ≈ 90), so its rim can never enter
        /// the frame. The "infinite table": geometry ends past visibility;
        /// the omni's falloff has already dimmed it to black out there.
        static let feltSpan: Float = 500
    }

    private func setUpTable() {
        // A thin box, not SCNFloor: the floor's reflection pass (FloorPass)
        // spams the log every frame even at reflectivity = 0 — the geometry
        // alone opts into the pass. A box never creates it, and gives the
        // felt a real UV-mapped surface for texture work. TD-4 discharged.
        let feltMaterial = SCNMaterial()
        let feltAppearance = theme.appearance.felt
        feltMaterial.diffuse.contents =
            (feltAppearance.usesImage ? UserImageStore.felt.load() : nil)
            ?? feltAppearance.color.uiColor
        feltMaterial.roughness.contents = NSNumber(1) // matte felt
        feltMaterial.specular.contents = UIColor.black
        // A photo felt tiles at its old density across the bigger box:
        // repeat-wrap + a UV scale factor instead of stretching — inert
        // when `diffuse.contents` is a plain color.
        feltMaterial.diffuse.wrapS = .repeat
        feltMaterial.diffuse.wrapT = .repeat
        feltMaterial.diffuse.mipFilter = .linear
        feltMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(
            Bounds.feltSpan / Bounds.span, Bounds.feltSpan / Bounds.span, 1)
        let felt = SCNBox(width: CGFloat(Bounds.feltSpan),
                          height: CGFloat(Bounds.thickness),
                          length: CGFloat(Bounds.feltSpan), chamferRadius: 0)
        // One shared instance across the six face slots: mutating it later
        // (applyAppearance) updates every face at once.
        felt.materials = Array(repeating: feltMaterial, count: 6)
        let floor = SCNNode(geometry: felt)
        floor.name = NodeName.felt
        // Same convention as the walls: center sits half a thickness below,
        // so the top face lands exactly on floorY — the contact plane the
        // dice rest on is unchanged.
        floor.position.y = Bounds.floorY - Bounds.thickness / 2
        // The *visual* felt outspans the play volume; the collider stays
        // table-sized — `shape: nil` would derive a 500-unit floor body
        // from the node's geometry.
        floor.physicsBody = .tableBody(shape: SCNPhysicsShape(
            geometry: SCNBox(width: CGFloat(Bounds.span),
                             height: CGFloat(Bounds.thickness),
                             length: CGFloat(Bounds.span), chamferRadius: 0)))
        scene.rootNode.addChildNode(floor)

        // Thin boxes, not the ancestors' oriented planes: an axis-aligned box
        // needs no orientation math at all — `reposition`'s arbitrary-normal
        // matrix dance earns nothing here. But a box collider is *finite*, so
        // thickness matters: a die takes ~24 units/s of impulse (mass 1.0,
        // measured), and a solver step can carry it ~1 unit — 4 units of
        // thickness is a margin, not a guarantee. What bounds the speed is
        // `roll()` clearing velocity before each impulse.
        // Invisible colliders done the safe way: a node with no geometry
        // renders nothing, and the body carries an explicit shape instead of
        // deriving one. `isHidden` was measured to drop the static bodies
        // from the simulation on current SDKs (dice escaped every face —
        // see PR notes), so visibility and collision stay decoupled by
        // construction rather than by flag.
        func bound(_ size: SCNVector3, at position: SCNVector3) {
            let node = SCNNode()
            node.position = position
            node.physicsBody = .tableBody(shape: SCNPhysicsShape(
                geometry: SCNBox(
                    width: CGFloat(size.x), height: CGFloat(size.y),
                    length: CGFloat(size.z), chamferRadius: 0)))
            scene.rootNode.addChildNode(node)
        }

        // Each center sits half a thickness outside its inner face, so the
        // faces land exactly on the declared volume — and the spans pad past
        // the corners and the ceiling's top face.
        let wallY = (Bounds.floorY + Bounds.ceilingY) / 2
        bound(SCNVector3(Bounds.span, Bounds.thickness, Bounds.span),
              at: SCNVector3(0, Bounds.ceilingY + Bounds.thickness / 2, 0)) // ceiling
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
                (appearance.felt.usesImage ? UserImageStore.felt.load() : nil)
                ?? appearance.felt.color.uiColor
        }
        applyLighting(appearance.lighting, in: scene.rootNode)
        applyLighting(appearance.lighting, in: previewScene.rootNode)
        applyBackdrop(appearance.backdrop)
    }

    /// SceneKit's backdrop is two scene properties, and the same image
    /// serves both: `background` is the visible backdrop, and
    /// `lightingEnvironment` accepts the *same LDR image* as an IBL source
    /// (it would take an .hdr for true HDR probes, but LDR is legal — the
    /// light just lacks over-range dynamic range). RealityKit needs a dome
    /// mesh and an async EnvironmentResource build for the same two lines'
    /// worth of effect — the asymmetry is the M9d lesson, recorded in
    /// Design.md.
    private func applyBackdrop(_ backdrop: BackdropAppearance) {
        guard backdrop != appliedBackdrop else { return }
        appliedBackdrop = backdrop
        let image = BackdropImage.resolve(backdrop)
        scene.background.contents = image ?? UIColor.black
        scene.lightingEnvironment.contents = image
        scene.lightingEnvironment.intensity = CGFloat(BackdropIBL.intensity)
        // The preview shows the same environment — the backdrop is
        // lighting, so the die in the editor must answer to it too.
        previewScene.background.contents = image ?? UIColor.black
        previewScene.lightingEnvironment.contents = image
        previewScene.lightingEnvironment.intensity = CGFloat(BackdropIBL.intensity)
    }

    /// Environment-light tuning for the backdrop channel. A plain photo is
    /// LDR, so modest intensity — the analytic lights still carry the mood.
    private enum BackdropIBL {
        static let intensity: Double = 1.0
    }

    /// One mood per preset — the SceneKit mapping is omni intensity,
    /// shadow softness/darkness, and ambient fill level. Applies to any
    /// root node holding named lights, so the preview honors the picker.
    private func applyLighting(_ preset: LightingPreset, in rootNode: SCNNode) {
        let key = rootNode.childNode(withName: NodeName.keyLight, recursively: false)?.light
        let fill = rootNode.childNode(withName: NodeName.fillLight, recursively: false)?.light
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

    /// The preview world's staging — die-scale, so `Bounds` doesn't apply.
    private enum Preview {
        static let cameraPosition = SCNVector3(x: 0, y: 2.4, z: 3.2)
        static let keyPosition = SCNVector3(x: 0, y: 6, z: 4)
        static let fillWhiteness: CGFloat = 0.4
        static let spinX: CGFloat = 0.9
        static let spinY: CGFloat = 1.6
        static let spinDuration: TimeInterval = 3
    }

    /// The appearance editor's live preview: one die, a camera, lights —
    /// and nothing else. Reuses `makeDie` minus its physics (a statue has
    /// no table to hit). The die spins on a mixed axis so every face reads.
    /// Lights carry the table's names so `applyLighting` reaches them.
    private func setUpPreview() {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = Preview.cameraPosition
        previewScene.rootNode.addChildNode(camera)
        camera.look(at: SCNVector3Zero)

        let die = Self.makeDie(at: SCNVector3Zero,
                               appearance: theme.appearance.die)
        die.physicsBody = nil
        die.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: Preview.spinX, y: Preview.spinY, z: 0,
                               duration: Preview.spinDuration)))
        previewScene.rootNode.addChildNode(die)
        previewDie = die

        let key = SCNNode()
        key.name = NodeName.keyLight
        key.light = SCNLight()
        key.light?.type = .omni
        key.position = Preview.keyPosition
        previewScene.rootNode.addChildNode(key)
        let fill = SCNNode()
        fill.name = NodeName.fillLight
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.color = UIColor(white: Preview.fillWhiteness, alpha: 1)
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
    /// `shape` defaults to nil — derive the collider from the node's own
    /// geometry. The floor overrides it because its geometry is the
    /// oversized visual felt, not the play volume.
    static func tableBody(shape: SCNPhysicsShape? = nil) -> SCNPhysicsBody {
        let body = SCNPhysicsBody(type: .static, shape: shape)
        body.categoryBitMask = PhysicsCategory.table.rawValue
        body.collisionBitMask = PhysicsCategory.die.rawValue
        return body
    }
}
