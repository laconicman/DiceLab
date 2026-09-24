# Design

Decisions that shaped DiceLab, one per section: the decision, why, and the
alternative rejected. Authoritative over code comments when they disagree.

## Architecture: four-layer MVC

`App/` composes (`DiceLabApp`, `@main`, injects shared objects), `Features/Roll/`
holds the dice-table screen (`RollView` root view + `DiceTableController`, the
screen's dedicated controller), `Model/` holds domain value types.

No `RootView` exists yet — there is no top-level branch to put in it (YAGNI).
`Model/` holds `DieFace` (pure face-up math on `simd` quaternions) and
`RollResult` since M3 — kept SceneKit-free so the M7 port keeps them.

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

## SceneKit first, RealityKit later

- *Why:* we inherit working physics tuning (impulse values, rest detection,
  face-up reading) and SceneKit's scene-graph API is the gentler on-ramp. The M7
  port then teaches ECS-vs-scene-graph by contrast — the strongest single lesson
  in the project.
- *Cost:* SceneKit is soft-deprecated since iOS 26 (security patches only). See
  `TD-1` in <doc:TechDebt>. Nothing in Model or the view layer may assume
  SceneKit internals, so the port stays a controller-internals swap.

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
binds through `@Bindable` and holds zero state itself. Two `@State`s exist,
deliberately distinct kinds: `DiceLabApp.table` — app-root object ownership,
Apple's documented pattern for keeping a reference type alive — and
`RollView.showingSettings`, the textbook transient-UI case.

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

## Roll history is a session record, not a log

`history` holds the last 20 `RollResult`s (cleared when `dieCount` changes —
a result from a different dice set is meaningless). The strip shows the last
five, newest first; `RollResult` gained `Identifiable` so rows key by event
identity — identical totals are still distinct rolls.
