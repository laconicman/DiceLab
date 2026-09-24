# Roadmap

Milestone plan. Each milestone ends in a buildable, commit-worthy state.

## Done

- **M0 — Forensics.** Both ancestors verified building on Xcode 26; spec
  extracted (2–3 dice, tap/impulse roll, contact sound + haptics, rest
  detection with face-up reading).
- **M1 — SwiftUI shell.** `@main` → `RollView` → `SceneView` rendering a
  controller-owned `SCNScene` (camera + lighting only).
- **M2 — Physics world.** Chamfered-box dice, static walls, `SCNFloor`,
  `PhysicsCategory` masks, randomized impulses on `roll()`.
- **M3 — Outcome.** Rest detection via `SCNSceneRendererDelegate`, face-up
  reading (`boxUpIndex` ported GLK→`simd`), `RollResult` published; first
  Swift Testing coverage on the pure math.
- **M4 — Feel.** `CHHapticEngine` transients scaled by `collisionImpulse`;
  contact audio.
- **M5 — Looks.** Runtime-drawn pip face textures with geometry-derived
  material mapping, PBR materials, lighting/shadow tuning.

## Now

- **M6 — App features.** Settings sheet (dice count, ivory/onyx skin,
  haptics, camera-control — discharges TD-3), shake-to-roll, roll history.

## Next
- **M7 — RealityKit port.** `RealityView`, `PhysicsBodyComponent`/
  `CollisionComponent`; the comparative exercise that discharges `TD-1`.
