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
- **M6 — App features.** Settings sheet (dice count, ivory/onyx skin,
  haptics, camera-control — discharges TD-3), shake-to-roll, roll history.
- **M7 — RealityKit port.** `DiceTable` protocol, generic `RollScreen`
  chrome, `RealityView` + `PhysicsBodyComponent`/`CollisionComponent`,
  velocity-defined rest, per-body CCD; engine picker in settings.
  Deployment floor moved to iOS 18 (`RealityView`); discharges `TD-1`.

- **M8a — Feel parity + feedback split.** RealityKit `Toss` retuned ~3×
  (real-time gravity needs velocity-carrying impulses), explicit damping,
  livelier restitution; SceneKit's deprecated `collisionImpulse` (always 0
  on current SDKs) replaced by a closing-speed estimate; haptics and sound
  become two toggles; `-impulseLog` dev flag measures rolls.
- **M8b — Appearance model.** `Appearance`/`Theme`/`CodableColor` in
  `Model/` — the `CubeMaterialSettings` surface generalized (die/felt
  colors, finish channels, felt photo via `FeltImageStore`, lighting
  presets); per-engine translation incl. clearcoat; `settings.skin`
  migrates; `rollID` hardened to `Mutex` (contact/renderer read it
  off-main).

- **M8c — Appearance editor.** `AppearanceEditor` with live per-engine die
  preview (controller-owned preview worlds whose lights share the table's
  names, so the lighting picker previews lighting), edit-flips-to-custom
  binding, felt `PhotosPicker` behind a generation counter for stale
  imports, lighting presets; `AVSpeechSynthesizer` speaks settled results,
  keyed on `lastRoll.id` so repeat outcomes still announce; `-appearanceeditor`
  dev flag for preview QA. (PR #10)

## Planned — M9, device-feedback round

Decisions taken with the user after the first device session: camera stays
fitted on the dice after settling; backdrop is presets *plus* a user photo;
emission is a full per-part editor; voice roll is deferred until after the
string catalog exists.

- **M9a — Hygiene.** `SCNFloor`→plane (the FloorPass spams every frame even
  at `reflectivity = 0`, and a plane gives the felt a real UV for texture
  work); `DiceTable` gains `@MainActor` (discharges TD-9 — a non-isolated
  protocol can't be safely witnessed by actor-isolated classes);
  `TextureResource.init(image:)` replaces the deprecated `generate(from:)`;
  default dice count 3→2; settings-persistence audit.
- **M9b — Camera fit.** Dice below a speed threshold → ease the camera to
  fit all dice in frame; settle → snug framing on the result (it *is* the
  point of interest); next `roll()` eases back to wide. Plus faint
  transparent walls — the legacy affordance that makes bounds legible.
- **M9c — History panel.** Optional via a persisted settings toggle;
  `.ultraThinMaterial` background; capped near a quarter of the screen;
  tap/drag to expand toward the safe area. Row-tint scaffolded (neutral
  default) for future per-player colors.
- **M9d — Appearance II.** Editor hides material controls unless the theme
  is `.custom`; sheet detents; per-part emission (face color+intensity and
  pip color+intensity — "glowing pips" and "glowing body, dark pips" are
  both expressible); backdrop channel with procedural presets and an
  optional photo. On RealityKit the backdrop doubles as the IBL source —
  the real fix for the flat plastic look: `PhysicallyBasedMaterial` was
  designed to be lit by an environment, not two analytic lights.
- **M9e — Localization prep.** `.xcstrings` catalog, every user-facing
  string extracted. Voice-roll ("Say roll!") is deliberately deferred —
  mic permission + locale handling is a milestone of its own.

## Next

- Open learning surface: device-time haptic/tuning pass, scripted camera
  moments (would revisit TD-3's default-on toggle), a second skin family,
  or RealityKit-vs-SceneKit performance measurement. Voice-trigger design
  (Speech framework, permissions, per-locale grammar).
