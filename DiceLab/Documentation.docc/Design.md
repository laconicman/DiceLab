# Design

Decisions that shaped DiceLab, one per section: the decision, why, and the
alternative rejected. Authoritative over code comments when they disagree.

## Architecture: four-layer MVC

`App/` composes (`DiceLabApp`, `@main`, injects shared objects), `Features/Roll/`
holds the dice-table screen (`RollView` root view + `DiceTableController`, the
screen's dedicated controller), `Model/` holds domain value types.

No `RootView` exists yet — there is no top-level branch to put in it (YAGNI).
`Model/` is likewise empty until a domain type earns it.

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
- **Bounds are thin boxes, not oriented planes.** The ancestors computed an
  arbitrary-normal plane orientation via GLK matrices (`reposition`); our
  bounds are axis-aligned, and a collider wants thickness anyway — SceneKit
  exposes no per-body continuous collision detection, so a zero-thickness
  plane risks tunneling at high impulse. Boxes kill the math and the risk at
  once; `timeStep` is halved as a second line of defense.
- **Impulses are randomized per die.** Burke applied the same fixed torque
  `(1, 2, -1, 1)` to every die, correlating their rolls.
