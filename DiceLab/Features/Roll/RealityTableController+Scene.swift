import CoreMedia
import os
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
        setUpSimulation()
        spawnDice(dieCount)
        applyDynamics()
        setUpPreview()
        // Dice and felt already read the stored appearance at build —
        // the lighting rig is the one piece that waits for this pass.
        applyLighting(theme.appearance.lighting, in: root)
        applyLighting(theme.appearance.lighting, in: previewRoot)
        applyBackdrop(theme.appearance.backdrop)
    }

    /// The camera's rest pose (meters). `axis` — the direction fitting
    /// slides along — is the normalized home offset, so the view axis
    /// always passes exactly through the cluster centroid without ever
    /// re-aiming (orientation stays fixed; no `look(at:)` gimbal edge).
    private enum CameraHome {
        static let position = SIMD3<Float>(0, 0.42, 0.03)
        static let fieldOfView: Float = 55
        static var axis: SIMD3<Float> { simd_normalize(position) }
        static var distance: Float { simd_length(position) }
    }

    /// Scripted-fit tuning (M9b) — the SceneKit `Fit` in meters.
    /// `speed` gates: above it dice are flying and the camera holds home;
    /// the settle threshold is 0.02 m/s, so 0.10 is "final tumbling."
    private enum Fit {
        static let speed: Float = 0.10
        /// Per-axis breathing room: a die's silhouette half-diagonal
        /// (~2.6 cm) plus ~1.5 cm of visible felt — the extreme die sits
        /// inside the frame, not flush against it.
        static let padding: Float = 0.04
        /// Floor and far cap: the floor keeps a compact cluster or a lone
        /// die from filling the screen; the cap isn't a constant — it's
        /// "the widest cluster the volume can hold," computed per-frame.
        /// Each axis's worst case is a die center pinned at that wall —
        /// half-extent + padding.
        static let minDistance: Float = 0.22
        static var volumeExtents: SIMD2<Float> {
            .init(Bounds.halfX + padding, Bounds.halfZ + padding)
        }
        static let rate: Float = 5
        /// Converged-pose epsilon — ~2 mm at meter scale.
        static let epsilon: Float = 0.002
        /// A paused renderer resumes with the whole pause inside `dt`
        /// (damp ≈ 1 → snap). Capping at 100 ms keeps resumes gliding.
        static let maxDt: Float = 0.1
    }

    /// Per-frame camera framing, called from `update`. Target flips
    /// home↔fitted on the speed gate; the damped glide between them is the
    /// "one animation eases into another" the feature calls for. Once the
    /// fitted pose converges after a settle, `fitConverged` latches and the
    /// fit stops writing — between-rolls orbit gestures are then free,
    /// with no per-frame tug-of-war. `roll()` clears the latch.
    func updateCameraFit(dt rawDt: Float) {
        guard cameraFitEnabled, !fitConverged,
              let camera = cameraEntity else { return }
        let dt = min(rawDt, Fit.maxDt)
        let positions = dice.map { $0.position }
        let fastest = dice.compactMap { die -> Float? in
            guard let motion = die.components[PhysicsMotionComponent.self] else { return nil }
            return simd_length(motion.linearVelocity)
        }.max() ?? 0
        let box = CameraFit.boundingBox(of: positions, padding: Fit.padding)
        var distance = CameraFit.requiredDistance(
            xExtent: box.extents.x, zExtent: box.extents.y,
            verticalFieldOfView: CameraHome.fieldOfView,
            aspect: Float(viewAspect))
        let maxDistance = CameraFit.requiredDistance(
            xExtent: Fit.volumeExtents.x, zExtent: Fit.volumeExtents.y,
            verticalFieldOfView: CameraHome.fieldOfView,
            aspect: Float(viewAspect))
        distance = min(max(distance, Fit.minDistance), maxDistance)
        // One-way gate per roll (SceneKit twin has the same latch): near the
        // threshold the gate must not flap the camera target — once dice
        // flew and slowed, `fitArmed` holds until the next throw.
        if isRolling {
            fitSawFlight = fitSawFlight || fastest >= Fit.speed
            fitArmed = fitArmed || (fitSawFlight && fastest < Fit.speed)
        }
        let fitting = !positions.isEmpty && (!isRolling || fitArmed)
        let target = fitting
            ? box.center + CameraHome.axis * distance
            : CameraHome.position
        // NaN transforms never recover — snap instead of damping poison.
        if !camera.position.x.isFinite {
            camera.position = CameraHome.position
        }
        // Settled + arrived: snap the last millimeters and hand the camera
        // back to the user. Only when not rolling — dice may still drift
        // while the settle gate runs.
        if !isRolling, fitting,
           simd_distance(camera.position, target) < Fit.epsilon,
           abs(simd_dot(camera.orientation, cameraHomeOrientation)) > 0.9999 {
            camera.position = target
            camera.orientation = cameraHomeOrientation
            orbitPivot = box.center
            fitConverged = true
            return
        }
        camera.position = CameraFit.damp(
            camera.position, toward: target, rate: Fit.rate, dt: dt)
        // Orientation isn't the fit's knob — but a between-rolls orbit
        // should ease back to the rest pose, not linger. `CameraFit.damp`
        // guards the identical-quat NaN `simd_slerp` hits.
        camera.orientation = CameraFit.damp(
            camera.orientation, toward: cameraHomeOrientation,
            rate: Fit.rate, dt: dt)
    }

    /// Custom-orbit tuning (M11) — the stock `.orbit` control's feel,
    /// measured on it before it was replaced: 0.22° of rotation per point
    /// of finger travel, both axes alike. Dolly stays outside the dice and
    /// inside the backdrop dome (4 m); the fit's own range is 0.22–~1 m.
    private enum Orbit {
        static let degreesPerPoint: Float = 0.2
        static let radiusRange: ClosedRange<Float> = 0.08...2.0
    }

    /// One-finger drag, in points since the last event. Ignored while the
    /// fit owns the camera (`cameraFitEnabled && !fitConverged`) — the
    /// suppression TD-10 called impossible while the orbit belonged to
    /// RealityKit. Both deltas read negative: measured on the stock
    /// control, right and down are minus in this convention — the camera
    /// chases the finger's opposite, so the scene follows the finger.
    func orbit(by delta: CGSize) {
        guard let camera = orbitableCamera else { return }
        let perPoint = Orbit.degreesPerPoint * .pi / 180
        let pose = CameraOrbit.orbit(
            CameraOrbit.pose(of: camera.position, about: orbitPivot),
            azimuthDelta: -Float(delta.width) * perPoint,
            elevationDelta: -Float(delta.height) * perPoint,
            radiusScale: 1, radiusRange: Orbit.radiusRange)
        if DevFlags.cameraLog {
            print(String(format: "[DiceLab] orbit d=(%.1f,%.1f) -> az=%.1f° elev=%.1f° r=%.3f",
                         delta.width, delta.height,
                         pose.azimuth * 180 / .pi, pose.elevation * 180 / .pi, pose.radius))
        }
        place(camera, at: pose)
    }

    /// Pinch, as the ratio of this event's magnification to the last
    /// one's — magnification above 1 (pinch out) zooms in.
    func dolly(by scale: CGFloat) {
        guard let camera = orbitableCamera, scale.isFinite, scale > 0
        else { return }
        let pose = CameraOrbit.orbit(
            CameraOrbit.pose(of: camera.position, about: orbitPivot),
            azimuthDelta: 0, elevationDelta: 0,
            radiusScale: 1 / Float(scale), radiusRange: Orbit.radiusRange)
        if DevFlags.cameraLog {
            print(String(format: "[DiceLab] dolly x%.3f -> r=%.3f", scale, pose.radius))
        }
        place(camera, at: pose)
    }

    /// The camera, if the user may move it right now: control on, and the
    /// fit either off or latched.
    private var orbitableCamera: Entity? {
        guard cameraControlEnabled, fitConverged || !cameraFitEnabled
        else { return nil }
        return cameraEntity
    }

    private func place(_ camera: Entity, at pose: CameraOrbit.Pose) {
        let position = CameraOrbit.position(of: pose, about: orbitPivot)
        // A NaN transform blanks the frame for good (see the fit) — never
        // write one.
        guard position.x.isFinite, position.y.isFinite,
              position.z.isFinite else { return }
        camera.look(at: orbitPivot, from: position, relativeTo: nil)
    }

    private func setUpCamera() {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.01, far: 10, fieldOfViewInDegrees: CameraHome.fieldOfView))
        // ~45 cm above the felt, pulled slightly toward the viewer for the
        // same gentle tilt the SceneKit camera uses.
        camera.look(at: .zero, from: CameraHome.position, relativeTo: nil)
        root.addChild(camera)
        cameraEntity = camera
        cameraHomeOrientation = camera.orientation
    }

    /// `-boundsProbe` diagnostics: flags the first position a die is seen
    /// outside the play volume (naming the face it crossed) and dumps rest
    /// positions at settle.
    private static let probeLog = Logger(subsystem: "DiceLab", category: "bounds")

    func probeBounds() {
        guard DevFlags.boundsProbe else { return }
        for (i, die) in dice.enumerated() {
            let p = die.position
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
            let p = die.position
            Self.probeLog.notice("rest: die \(i) at \(p.x),\(p.y),\(p.z)")
            print("[DiceLab] rest: die \(i) at \(p.x),\(p.y),\(p.z)")
        }
    }

    /// Entities the appearance pass reaches for by name — the alternative
    /// is stored refs on the main class, and a name is honest enough for
    /// five fixed entities.
    private enum EntityName {
        static let felt = "felt"
        static let keyLight = "keyLight"
        static let fillLight = "fillLight"
        static let backdropDome = "backdropDome"
        static let iblProbe = "iblProbe"
    }

    private func setUpLighting() {
        // Key light: the `DirectionalLight` entity type — the bare component
        // exposes no shadow on iOS, the entity does.
        let light = DirectionalLight()
        light.name = EntityName.keyLight
        light.light.intensity = 2500
        light.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 1.0, depthBias: 4.0)
        light.look(at: .zero, from: [0.2, 1.0, 0.15], relativeTo: nil)
        root.addChild(light)

        // Fill: a dim point light above the table so shadow sides aren't
        // pitch black — iOS RealityKit has no ambient-light component.
        let fill = PointLight()
        fill.name = EntityName.fillLight
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
        /// Collider thickness — a *tunneling* margin, not a visual one.
        /// RealityKit's discrete check runs once per rendered frame: a die
        /// tossed at ~6 m/s travels ~0.10 m at 60 Hz (0.20 at a 30 fps dip),
        /// so a 0.04 slab is inside one step's reach whenever CCD misses.
        /// The inner face stays put regardless — each bound's position is
        /// `inner + thickness/2` — so the margin is free. 0.24 keeps a
        /// ~7 m/s solver spike inside at 30 fps.
        static let thickness: Float = 0.24
        static let span: Float = 0.60
        /// The felt's *visible* reach: past the backdrop dome's radius, so
        /// every sightline to its rim exits the dome first and the edge
        /// hides behind the dome wall — RealityKit's stand-in for the
        /// SceneKit fog dissolve. Collision stays `span`-sized.
        static let feltSpan: Float = 20
        static let dieEdge: Float = 0.03
        static let dieMass: Float = 0.02   // kg — impulse tuning assumes it
        /// The d20's circumradius: face-to-face ≈ 0.032 m against the
        /// cube's 0.03 edge — the same relative sizing as SceneKit's
        /// 2-unit radius against the 3-unit box.
        static let d20Radius: Float = 0.02
    }

    /// Friction/restitution pairs — named because they're the dials a device
    /// tuning pass would reach for first (TD-6). Restitution sits higher than
    /// SceneKit's implicit defaults: real-time gravity gives each bounce less
    /// airtime than `speed = 3` physics, so the energy has to come back at
    /// contact rather than hang in the air.
    enum PhysicsTune {
        static let tableFriction: Float = 0.6
        static let tableRestitution: Float = 0.45
        static let dieFriction: Float = 0.4
        static let dieRestitution: Float = 0.6
        /// Below SceneKit's implicit 0.1s — heavy damping reads as
        /// mid-air molasses at meter scale; felt friction does the stopping.
        /// Also the `viscosity = 0` baseline for `applyDynamics`.
        static let linearDamping: Float = 0.05
        static let angularDamping: Float = 0.05
        /// Per-unit drag gain: viscosity 1 → damping 0.4, the dial's 2 →
        /// 0.75 — mid-air molasses at the top end.
        static let viscosityGain: Float = 0.35
    }

    /// Throw-feel tuning: a `PhysicsSimulationComponent` on `root` makes it
    /// the simulation entity for everything below (community guidance is to
    /// host it on the *parent* of physics bodies, not on a body itself —
    /// odd behavior otherwise). `clock` is the dial the SceneKit table gets
    /// from `physicsWorld.speed`: a `CMTimebase` sourced on the host clock,
    /// whose `rate` scales simulated seconds per wall second. Verified on
    /// simulator via `-impulseLog`: settle wall-time tracks ~1/rate —
    /// monotonic but sub-linear, so the solver likely clamps per-frame dt.
    /// `gravity` and `solverIterations` ride defaults.
    private func setUpSimulation() {
        var timebase: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(
                allocator: nil,
                sourceClock: CMClockGetHostTimeClock(),
                timebaseOut: &timebase) == noErr,
              let timebase
        else { return }
        simulationTimebase = timebase
        var simulation = PhysicsSimulationComponent()
        simulation.clock = timebase
        root.components.set(simulation)
    }

    /// Re-tunes the live world in place. `CMTimebaseSetRate` rewrites the
    /// clock in place — no component swap — and damping is a property on
    /// each die's `PhysicsBodyComponent`; both are mid-roll safe. Pace and
    /// viscosity stay orthogonal the same way the SceneKit side does:
    /// damping is sim-space, so `pace` changes playback, `viscosity`
    /// changes the trajectory.
    func applyDynamics() {
        let pace = DevFlags.paceOverride ?? dynamics.pace
        if let timebase = simulationTimebase {
            CMTimebaseSetRate(timebase, rate: Float64(pace))
            if DevFlags.impulseLog {
                print("[DiceLab] rk pace=\(pace) rate=\(CMTimebaseGetRate(timebase))")
            }
        }
        let damping = PhysicsTune.linearDamping
            + PhysicsTune.viscosityGain * Float(dynamics.viscosity)
        for die in dice {
            guard var body = die.components[PhysicsBodyComponent.self] else { continue }
            body.linearDamping = damping
            body.angularDamping = damping
            die.components.set(body)
        }
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
        // The mesh overshoots the dome's radius so the rim is always hidden
        // behind it; the collision shape stays table-sized.
        let felt = Entity()
        felt.name = EntityName.felt
        let feltShape = ShapeResource.generateBox(
            size: [Bounds.span, Bounds.thickness, Bounds.span])
        felt.components.set(ModelComponent(
            mesh: .generateBox(size: [Bounds.feltSpan, Bounds.thickness, Bounds.feltSpan]),
            materials: [Self.feltMaterial(for: theme.appearance.felt)]))
        felt.components.set(CollisionComponent(shapes: [feltShape]))
        felt.components.set(PhysicsBodyComponent(
            shapes: [feltShape], density: 1,
            material: Self.tableMaterial, mode: .static))
        felt.position = [0, Bounds.floorY - Bounds.thickness / 2, 0]
        root.addChild(felt)

        // Walls + ceiling: collision-only entities — no ModelComponent, so
        // nothing renders. That's the ECS version of `isHidden`: physics is
        // a component, visuals are a component, and a wall needs only one.
        // (The M9b translucent panels are gone — fully invisible is the ask.)
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

        // The visible backdrop is geometry, not a scene property — iOS
        // RealityKit has no `scene.background` (that's SceneKit's
        // convenience). An inside-out unlit sphere plays skybox: front-face
        // culling leaves the inward surfaces, no winding-flip scale needed.
        // It stays enabled even with no backdrop — a disabled dome leaves
        // the `RealityView` transparent where the felt doesn't reach, and
        // the window behind it renders as a blank white screen.
        // Radius keeps the camera (max retreat < 1 m) and its far plane
        // (10 m) comfortably inside.
        let dome = ModelEntity(
            mesh: .generateSphere(radius: Backdrop.domeRadius),
            materials: [Self.domeMaterial()])
        dome.name = EntityName.backdropDome
        root.addChild(dome)

        // The IBL probe's host — an inert entity `applyBackdrop` sets and
        // removes `VirtualEnvironmentProbeComponent` on. A component, not a
        // light: physics is a component, lighting influence is too.
        let probe = Entity()
        probe.name = EntityName.iblProbe
        root.addChild(probe)
    }

    /// Backdrop staging constants — the dome is big enough to read as
    /// "the room," small enough to stay inside the 10 m far plane.
    private enum Backdrop {
        static let domeRadius: Float = 4
    }

    /// The dome's idle material — opaque black, inside-out. Any backdrop
    /// image swaps it for the textured variant; `.none` lands here so the
    /// view is never transparent.
    private static func domeMaterial() -> UnlitMaterial {
        var material = UnlitMaterial(color: .black)
        material.faceCulling = .front
        return material
    }

    /// Spawn geometry in meters — same spread rule as SceneKit, scaled ÷100.
    private enum Spawn {
        static let span: Float = 0.16
        static let maxSpacing: Float = 0.045
        /// The meter-scale d20 stagger: the 0.032 spacing at six dice is
        /// under a radius-0.02 d20's ~0.034 x footprint, and the row
        /// can't widen — so dice zig-zag ±0.02 in z, landing ≈0.051
        /// apart, past the 0.04 diameter in any orientation.
        static let d20Stagger: Float = 0.02
    }

    /// Spawn slots centered on the table midline; a lone die or a cube
    /// row stays on z = 0. Static and pure so tests can pin the geometry
    /// — the mirror of the SceneKit version.
    static func spawnPositions(count: Int, shape: DieShape) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        let spacing = min(Spawn.maxSpacing, Spawn.span / Float(max(count - 1, 1)))
        let first = -spacing * Float(count - 1) / 2
        return (0..<count).map {
            let stagger = shape == .d20 && count > 1
                ? ($0.isMultiple(of: 2) ? Spawn.d20Stagger : -Spawn.d20Stagger)
                : 0
            return SIMD3(first + spacing * Float($0), 0, stagger)
        }
    }

    func spawnDice(_ count: Int) {
        for position in Self.spawnPositions(count: count, shape: dieShape) {
            let die = Self.makeDie(at: position, shape: dieShape,
                                   appearance: theme.appearance.die)
            dice.append(die)
            root.addChild(die)
        }
    }

    /// Re-skins the whole table in place — dice, felt, and lighting preset.
    /// Materials are just a component property, so the swap is a straight
    /// reassignment; felt and lights are found by name.
    func applyAppearance() {
        let appearance = theme.appearance
        let materials = Self.materials(shape: dieShape, appearance: appearance.die)
        for die in dice {
            die.components[ModelComponent.self]?.materials = materials
        }
        previewDie?.components[ModelComponent.self]?.materials = materials
        if let felt = root.findEntity(named: EntityName.felt) {
            felt.components[ModelComponent.self]?.materials =
                [Self.feltMaterial(for: appearance.felt)]
        }
        applyLighting(appearance.lighting, in: root)
        applyLighting(appearance.lighting, in: previewRoot)
        applyBackdrop(appearance.backdrop)
    }

    /// The same image does backdrop double duty, the RealityKit way: the
    /// *visible* backdrop is the dome's unlit texture, and the *lighting*
    /// backdrop is a `VirtualEnvironmentProbeComponent` built async
    /// (equirect → cube `TextureResource` → `EnvironmentResource` → probe).
    /// SceneKit did both in two scene-property lines — here the visible
    /// part is geometry and the lighting part is a generated component.
    /// An LDR photo still works as a probe source; it just lights without
    /// the over-range dynamic range a real .hdr environment carries.
    private func applyBackdrop(_ backdrop: BackdropAppearance) {
        guard backdrop != appliedBackdrop else { return }
        appliedBackdrop = backdrop
        backdropGeneration += 1
        let generation = backdropGeneration
        let dome = root.findEntity(named: EntityName.backdropDome)
        // The probe lives in both worlds — the preview die must answer to
        // the same environment the table does.
        let probes = [root, previewRoot].compactMap {
            $0.findEntity(named: EntityName.iblProbe)
        }
        guard let image = BackdropImage.resolve(backdrop),
              let cgImage = image.cgImage else {
            // No backdrop → plain black dome, still enabled: disabling it
            // would leave the RealityView transparent where the felt
            // doesn't reach — a white screen in light mode.
            dome?.components[ModelComponent.self]?.materials =
                [Self.domeMaterial()]
            for probe in probes {
                probe.components.remove(VirtualEnvironmentProbeComponent.self)
            }
            return
        }
        if let texture = try? TextureResource(
            image: cgImage, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.faceCulling = .front
            dome?.components[ModelComponent.self]?.materials = [material]
        }
        Task {
            var environment: EnvironmentResource?
            if let cube = try? await TextureResource(
                cubeFromEquirectangular: cgImage,
                options: .init(semantic: .color)) {
                environment = try? await EnvironmentResource(
                    cube: cube, options: .init())
            }
            guard generation == backdropGeneration else { return }
            for probe in probes {
                if let environment {
                    probe.components.set(VirtualEnvironmentProbeComponent(
                        source: .single(.init(environment: environment))))
                } else {
                    // Conversion failed — stale environment light is worse
                    // than none; the analytic rig carries the scene.
                    probe.components.remove(
                        VirtualEnvironmentProbeComponent.self)
                }
            }
        }
    }

    /// One mood per preset — RealityKit's mapping is key/fill intensity.
    /// Applies under any named-light parent, so the preview honors the picker.
    private func applyLighting(_ preset: LightingPreset, in parent: Entity) {
        let key = parent.findEntity(named: EntityName.keyLight) as? DirectionalLight
        let fill = parent.findEntity(named: EntityName.fillLight) as? PointLight
        switch preset {
        case .studio:   key?.light.intensity = 2500; fill?.light.intensity = 500
        case .soft:     key?.light.intensity = 1800; fill?.light.intensity = 800
        case .dramatic: key?.light.intensity = 3400; fill?.light.intensity = 200
        }
    }

    /// Color felt or the user's photo — `usesImage` without a loadable file
    /// falls back to the flat color rather than a broken texture.
    private static func feltMaterial(for felt: FeltAppearance) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if felt.usesImage, let cgImage = UserImageStore.felt.load()?.cgImage,
           let texture = try? TextureResource(
               image: cgImage, options: .init(semantic: .color)) {
            material.baseColor = .init(tint: .white, texture: .init(texture))
            // The felt mesh outspans the photo — a UV transform tiles it at
            // the old density instead of stretching it once across.
            material.textureCoordinateTransform.scale =
                SIMD2<Float>(repeating: Bounds.feltSpan / Bounds.span)
        } else {
            material.baseColor = .init(tint: felt.color.uiColor)
        }
        material.roughness = 1.0
        return material
    }

    /// The die mesh is shared across all dice — generated once, the same
    /// caching rule the SceneKit side applies to face images.
    static let dieMesh = MeshResource.generateBox(
        width: Bounds.dieEdge, height: Bounds.dieEdge, depth: Bounds.dieEdge,
        cornerRadius: Bounds.dieEdge * 0.06, splitFaces: true)

    /// The d20's mesh, built from `Icosahedron`'s model data: flat-shaded —
    /// every face owns its three vertices — with one `perFace` material
    /// index per triangle so the twenty faces take twenty materials the
    /// way the box's split faces take six. `MeshDescriptor` texture v runs
    /// UP, opposite the image space the shared UV template is written in,
    /// so v is flipped on the way in. `try!` is safe: the descriptor is
    /// constant geometry, so a failure is a programming error the tests
    /// pin — REVIEW.md's no-force-unwrap rule is about loadable assets.
    static let d20Mesh: MeshResource = {
        var descriptor = MeshDescriptor(name: "d20")
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for (index, face) in Icosahedron.faces.enumerated() {
            let normal = Icosahedron.normals[index]
            for (vertex, uv) in zip(
                [face.x, face.y, face.z].map { Icosahedron.vertices[$0] },
                DieFaceTexture.triangleUVs) {
                positions.append(vertex * Bounds.d20Radius)
                normals.append(normal)
                uvs.append(SIMD2(uv.x, 1 - uv.y))
            }
        }
        descriptor.positions = .init(positions)
        descriptor.normals = .init(normals)
        descriptor.textureCoordinates = .init(uvs)
        descriptor.primitives = .triangles((0..<60).map { UInt32($0) })
        descriptor.materials = .perFace((0..<20).map { UInt32($0) })
        return try! MeshResource.generate(from: [descriptor])
    }()

    /// One selector for the table dice and the preview — both must
    /// resolve a shape to the same mesh, or the editor would preview a
    /// die the table never rolls.
    static func dieMesh(for shape: DieShape) -> MeshResource {
        switch shape {
        case .d6: dieMesh
        case .d20: d20Mesh
        }
    }

    /// The preview world's staging — meter-scale like the table (die ≈ 3 cm).
    private enum Preview {
        static let cameraPosition = SIMD3<Float>(0, 0.055, 0.08)
        static let cameraFieldOfView: Float = 40
        static let keyDirection = SIMD3<Float>(0.2, 1.0, 0.15)
        static let keyIntensity: Float = 2500
        static let fillPosition = SIMD3<Float>(0, 0.15, 0.1)
        static let fillIntensity: Float = 400
        static let fillAttenuation: Float = 1
    }

    /// The appearance editor's live preview: one die, a camera, lights —
    /// and nothing else. No physics components: a statue has no table to
    /// hit. The preview `RealityView` spins it per-frame. Lights carry the
    /// table's names so `applyLighting` reaches them.
    private func setUpPreview() {
        let camera = Entity()
        camera.components.set(PerspectiveCameraComponent(
            near: 0.001, far: 2, fieldOfViewInDegrees: Preview.cameraFieldOfView))
        camera.look(at: .zero, from: Preview.cameraPosition, relativeTo: nil)
        previewRoot.addChild(camera)

        let die = ModelEntity(
            mesh: Self.dieMesh(for: dieShape),
            materials: Self.materials(shape: dieShape,
                                      appearance: theme.appearance.die))
        previewRoot.addChild(die)
        previewDie = die

        let key = DirectionalLight()
        key.name = EntityName.keyLight
        key.light.intensity = Preview.keyIntensity
        key.look(at: .zero, from: Preview.keyDirection, relativeTo: nil)
        previewRoot.addChild(key)
        let fill = PointLight()
        fill.name = EntityName.fillLight
        fill.light.intensity = Preview.fillIntensity
        fill.light.attenuationRadius = Preview.fillAttenuation
        fill.position = Preview.fillPosition
        previewRoot.addChild(fill)

        // Same probe host as the table — `applyBackdrop` sets the shared
        // environment on both, no dome needed in a one-die world.
        let probe = Entity()
        probe.name = EntityName.iblProbe
        previewRoot.addChild(probe)
    }

    private static func makeDie(at position: SIMD3<Float>, shape dieShape: DieShape,
                                appearance: DieAppearance) -> ModelEntity {
        // `ModelEntity`, not bare `Entity`: the impulse methods
        // (`applyLinearImpulse`/`applyAngularImpulse`) hang off
        // `HasPhysicsBody`, which only the model-entity subclass conforms to.
        let die = ModelEntity(mesh: dieMesh(for: dieShape),
                              materials: materials(shape: dieShape,
                                                   appearance: appearance))
        die.position = position

        // The box's collider stays the primitive box; the d20's comes from
        // its mesh's convex hull — `generateConvex` is the documented path
        // for arbitrary geometry.
        let shape: ShapeResource = switch dieShape {
        case .d6:
            ShapeResource.generateBox(size: .init(repeating: Bounds.dieEdge))
        case .d20:
            ShapeResource.generateConvex(from: d20Mesh)
        }
        var body = PhysicsBodyComponent(
            shapes: [shape], mass: Bounds.dieMass,
            material: dieMaterial, mode: .dynamic)
        // RealityKit exposes per-body continuous collision detection — the
        // exact API SceneKit withholds. The walls' thickness is still a
        // margin, but CCD is the guarantee the SceneKit scene can't buy.
        body.isContinuousCollisionDetectionEnabled = true
        body.linearDamping = PhysicsTune.linearDamping
        body.angularDamping = PhysicsTune.angularDamping
        die.components.set(body)
        die.components.set(CollisionComponent(shapes: [shape]))
        // Velocity lives on the motion component — added so `update` can
        // *read* rest, not just so impulses can write motion.
        die.components.set(PhysicsMotionComponent())
        return die
    }

    /// One material per part in the mesh's own order — derived from
    /// geometry, never assumed (the M5 rule, kept). A split-faces box has
    /// one part per face and so does the d20's perFace mesh; each part's
    /// centroid direction resolves to a face value via
    /// `DieFace.value(facing:)` — the same authority the reported face-up
    /// value uses.
    static func materials(shape: DieShape,
                          appearance: DieAppearance) -> [any RealityKit.Material] {
        let mesh = dieMesh(for: shape)
        var slots: [any RealityKit.Material] = (0..<mesh.expectedMaterialCount)
            .map { _ in PhysicallyBasedMaterial() }
        for model in mesh.contents.models {
            for part in model.parts {
                guard part.materialIndex < slots.count else { continue }
                let value = DieFace.value(facing: centroid(of: part), shape: shape)
                slots[part.materialIndex] = faceMaterial(
                    value, shape: shape, appearance: appearance)
            }
        }
        return slots
    }

    private static func faceMaterial(_ value: Int, shape: DieShape,
                                     appearance: DieAppearance) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let image = DieFaceTexture.images(for: appearance,
                                             shape: shape)[value - 1].cgImage,
           let texture = try? TextureResource(
               image: image, options: .init(semantic: .color)) {
            material.baseColor = .init(tint: .white,
                                       texture: .init(texture))
        } else {
            // Texture generation shouldn't sink the die — fall back to the
            // flat face color; the die is still playable.
            material.baseColor = .init(tint: appearance.faceColor.uiColor)
        }
        material.roughness = .init(floatLiteral: Float(appearance.roughness))
        material.metallic = .init(floatLiteral: Float(appearance.metalness))
        material.clearcoat = .init(floatLiteral: Float(appearance.clearcoat))
        // Emission is a texture here too, with `emissiveIntensity` carrying
        // the peak — the same split as the SceneKit `emission` channel.
        // The color parameter must stay unset: a non-black `EmissiveColor`
        // color adds a flat wash on top of the texture rather than tinting
        // it (verified on-device — `color: .white` whites out the face).
        if let emissionImages = DieFaceTexture.emissionImages(for: appearance,
                                                              shape: shape),
           let cgImage = emissionImages[value - 1].cgImage,
           let texture = try? TextureResource(
               image: cgImage, options: .init(semantic: .color)) {
            material.emissiveColor = .init(texture: .init(texture))
            material.emissiveIntensity = Float(appearance.emission.intensity)
        }
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
}
