# Roadmap

Milestone plan. Each milestone ends in a buildable, commit-worthy state.

## Done

- **M0 — Forensics.** Both ancestors verified building on Xcode 26; spec
  extracted (2–3 dice, tap/impulse roll, contact sound + haptics, rest
  detection with face-up reading).
- **M1 — SwiftUI shell.** `@main` → `RollView` → `SceneView` rendering a
  controller-owned `SCNScene` (camera + lighting only).

## Now

- **M2 — Physics world.** Chamfered-box dice, static walls, `SCNFloor`,
  `PhysicsCategory` masks, randomized impulses on `roll()`.

## Next

- **M3 — Outcome.** Rest detection via `SCNSceneRendererDelegate`, face-up
  reading (`boxUpIndex` ported GLK→`simd`), `RollResult` published; first
  Swift Testing coverage on the pure math.
- **M4 — Feel.** `CHHapticEngine` transients scaled by `collisionImpulse`;
  contact audio.
- **M5 — Looks.** PBR materials, runtime face textures (both ancestor skins as
  switchable styles), lighting/shadow tuning, optional `SCNShaderModifier`.

## Later

- **M6 — App features.** Dice count, shake-to-roll, roll history, settings
  (incl. camera-control decision).
- **M7 — RealityKit port.** `RealityView`, `PhysicsBodyComponent`/
  `CollisionComponent`; the comparative exercise that discharges `TD-1`.
