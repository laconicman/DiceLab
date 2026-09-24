# Design

Decisions that shaped DiceLab, one per section: the decision, why, and the
alternative rejected. Authoritative over code comments when they disagree.

## Architecture: four-layer MVC

`App/` composes (`DiceLabApp`, `@main`, injects shared objects), `Features/Roll/`
holds the dice-table screen (`RollScreen` — engine-agnostic chrome — plus one
thin view per engine and the two controllers), `Model/` holds domain value
types.

No `RootView` exists yet — the engine `switch` in `DiceLabApp` is the whole
top-level branch (YAGNI). `Model/` holds `DieFace` (pure face-up math on
`simd` quaternions), `RollResult`, `DiceTable` (the engine contract) and
`DiceEngine` — engine-free, which is what let M7 be a controller-level swap.

## The scene lives in the controller

`DiceTableController` (`@Observable`) owns the `SCNScene`; `RollView` renders it
through `SceneView`.

- *Why:* a physics world is domain state, not view state. `@State` in a view
  dies with the view's *identity* — sheets, navigation, conditional display can
  all re-identity a view and reset the world mid-roll. `@State` also tracks the
  property, not the object, so nothing inside a scene could publish anyway.
  Apple's "Managing user interface state" doc draws exactly this line.
- *Rejected:* `@State var scene = SCNScene()` in `RollView` — survives struct
  recreation but couples world lifetime to view identity, and blocks publishing.
- *Rule of thumb this encodes:* `SceneView` is the view; `SCNScene` is the model.

## SceneView, not UIViewRepresentable

`SceneView` (SwiftUI's native SceneKit bridge, iOS 14+) already covers what we
need: scene injection, renderer delegate, antialiasing, camera control.

- *Rejected for now:* wrapping `SCNView` in `UIViewRepresentable` — the escape
  hatch for `SCNView`-only APIs (custom gestures, overlays). If a milestone needs
  one, only `RollView` changes.

## SceneKit first, RealityKit later — then both

- *Why:* we inherited working physics tuning (impulse values, rest detection,
  face-up reading) and SceneKit's scene-graph API was the gentler on-ramp. The
  M7 port then taught ECS-vs-scene-graph by contrast — the strongest single
  lesson in the project, see "Two engines, one table" below.
- *Resolution:* M7 landed — both engines ship side by side behind `DiceTable`,
  SceneKit remains the default. `TD-1` discharged: the deprecation risk is now
  a user-selectable switch, not a rewrite hanging over the project.
- *Deployment floor moved to iOS 18:* `RealityView` is iOS 18+ on iOS (the
  iOS 17 alternative — `UIViewRepresentable` around `ARView` — is a dead-end
  API). The floor rose for exactly this reason.

## Port, don't copy — what the ancestors got wrong

Deliberate divergences from `DiceRollDemo`/`RollingDice`, each a bug class the
old code carried:

- **Physics masks are named.** Old code wrote `node.categoryBitMask = 1`
  (render-only mask, dead code for physics) while contacts worked by accident
  of defaults: `die.physicsBody.contactTestBitMask = 1` ANDed against the walls'
  default body category. `PhysicsCategory` makes the three masks explicit.
- **Walls are static, not kinematic.** Kinematic is for code-moved objects;
  static is the correct (and cheaper) type for immovable geometry.
- **Bounds are boxes, not oriented planes.** The ancestors computed an
  arbitrary-normal plane orientation via GLK matrices (`reposition`); our
  bounds are axis-aligned, so `reposition`'s math earns nothing here. But a
  box collider is finite where a plane is not: dice take ~24 units/s of
  impulse (body mass is 1.0, measured), so bounds are 4 units thick
  (`DiceTableController.Bounds`), and `roll()` clears velocity before each
  impulse — bounded speed is what makes the margin real. `timeStep` is
  halved as a second line of defense.
- **Impulses are randomized per die.** Burke applied the same fixed torque
  `(1, 2, -1, 1)` to every die, correlating their rolls.
- **Haptics come from `collisionImpulse`, not `penetrationDistance`** — the
  ancestors scaled feedback by overlap depth (a solver artifact); impulse in
  N·s is the physics. `CHHapticEngine` also synthesizes the audio knock in
  the same pattern, replacing undocumented `AudioServices` system-sound IDs.

## Face textures are generated, and the mapping is measured

`SCNBox` exposes one geometry element; its six material slots map to
contiguous triangle groups inside it — measured order `+Z, +X, −Z, −X, +Y,
−Y`. `DieFaceTexture.materialAxes` derives each slot's face axis from vertex
data (mean position = outward normal) rather than hardcoding that order, so
the visible pips can never silently disagree with `DieFace`'s value↔axis
authority. Textures are `UIGraphicsImageRenderer`-drawn pips — no assets.

- *Deferred to M6:* the ancestors' alternate skin and a style switcher —
  that is settings UI, not material work. `SCNShaderModifier` stays out of
  scope until PBR proves insufficient.
- *Confirmed at runtime:* `SCNBox(chamferRadius:)` produces identical
  triangle layout, so the derivation survives the tumble-friendly chamfer.

## Settings live in the controller, persisted by it

M6 adds dice count, skin, haptics, and camera-control toggles. They live on
`DiceTableController` — not `@AppStorage` in a view — because they shape the
scene, which is controller state (same argument as scene ownership). Each
is a stored property with `didSet`: persist to `UserDefaults`, apply to the
world (`respawnDice`, `applySkin`, `haptics.isEnabled`). `SettingsView`
binds through `@Bindable` and holds zero state itself. State lives in
deliberately distinct kinds: `DiceLabApp`'s `@State` controllers — app-root
object ownership, Apple's documented pattern for keeping a reference type
alive — `DiceLabApp.engine` (`@AppStorage`, picks which controller exists),
and `RollScreen.showingSettings`, the textbook transient-UI `@State`.

- *Consequence:* changing `dieCount` rebuilds the dice. `respawnDice` bumps
  `rollID` and clears `isRolling`/`lastRoll`, so a settle task queued for
  the discarded dice can never publish a result for dice that no longer
  exist — the same stale-publish class Devin caught in M3, handled the
  same way.
- *TD-3 discharged:* camera control is now a user toggle, default on — this
  is a learning toy, free orbiting is a feature until scripted camera work
  arrives.

## Shake-to-roll rides the responder chain

SwiftUI has no shake gesture, and `UIDevice.deviceDidShakeNotification` only
posts when *nothing* consumed `motionEnded` — depending on that is fragile.
`ShakeDetector` is an invisible `UIView` that claims first responder:
motion events walk the responder chain (object graph, not hit-testing), so
zero size and no visuals are fine. This is the one place the
`UIViewRepresentable` escape hatch earns its keep.

## Two engines, one table — what the port actually taught

M7 put both engines behind `DiceTable` (`Model/DiceTable.swift`): one protocol
for everything a view may observe or toggle. `RollScreen<Table: DiceTable>`
holds all chrome; `SceneKitRollView`/`RealityRollView` are ~20-line shims that
only differ in the scene widget. The engine picker lives in Settings, written
to `settings.engine` — the one piece of app-level state, because it selects
which controller *exists*. Both controllers read the same `settings.*` keys,
so dice count/skin/haptics survive an engine switch.

The port's real findings, SceneKit → RealityKit:

- **Ownership inverts.** `DiceTableController` owns the `SCNScene` and views
  render it. RealityKit owns the container: `RealityView`'s content closure
  runs once, receives `content.camera = .virtual` (the iOS default is
  world-tracking AR), the entity graph, and the two event subscriptions.
  The controller keeps mutating entities imperatively afterward.
- **Rest is a definition, not a flag.** SceneKit hands you
  `physicsBody.isResting`; RealityKit exposes only velocity, read through
  `PhysicsMotionComponent` on a per-frame `SceneEvents.Update`. Ours:
  |v| < 2 cm/s and |ω| < 0.3 rad/s sustained 15 frames. Honest bookkeeping —
  and it survives an engine swap.
- **CCD exists on RealityKit.** `isContinuousCollisionDetectionEnabled` is
  the per-body tunneling guard SceneKit withholds (Bullet has it, the API
  doesn't surface it). The walls' thickness becomes a formality; on SceneKit
  it was the whole defense.
- **Physics tuning never ports.** Meters vs SceneKit units (÷100), real-time
  gravity vs `physicsWorld.speed = 3`, gram-scale masses vs mass 1.0. The
  impulse *shape* ported; every constant was re-tuned. Haptics needed a
  per-engine `maxImpulse` (25 vs 0.3) — same normalization, different scale.
- **Impulses need `ModelEntity`.** `applyLinearImpulse`/`applyAngularImpulse`
  hang off `HasPhysicsBody` — bare `Entity` doesn't conform. In SceneKit any
  node takes a body; in ECS the *capability* is a type-level fact.
- **Isolation flipped.** The SceneKit controller is an `NSObject` defending
  `@Observable` state from the render thread with `Task { @MainActor }`
  hops. The RealityKit controller is `@MainActor` throughout — RealityKit
  itself is (`MeshResource` included); there is no foreign thread to defend.
- **The measured-mapping rule held.** `generateBox(splitFaces: true)` gives
  one `MeshResource.Part` per face; each part's vertex centroid is its face
  normal — the same centroid trick that decoded `SCNBox`'s index buffer in
  M5. Pips still can't disagree with `DieFace.up`.
- **Invisible bounds got simpler.** No `isHidden` — an entity without a
  `ModelComponent` renders nothing. Physics is a component, not a node type.

*Verified end to end:* a `-autoroll` launch argument drives
throw→settle→publish without manual tapping — on both engines the banner and
history agree with the pips on the felt.

## Roll history is a session record, not a log

`history` holds the last 20 `RollResult`s (cleared when `dieCount` changes —
a result from a different dice set is meaningless). The strip shows the last
five, newest first; `RollResult` gained `Identifiable` so rows key by event
identity — identical totals are still distinct rolls.

## Where state lives, after M7

- `DiceLabApp.engine` — `@AppStorage("settings.engine")`, the app-level
  choice of which controller exists. Plus two `@State` controllers — the
  documented Apple pattern for root-owned reference objects.
- Per-controller settings (`dieCount`, `skin`, `haptics`, `camera`) —
  controller `didSet` → `UserDefaults`, shared keys across engines.
- `RollScreen.showingSettings` — `@State`, the textbook transient case.
