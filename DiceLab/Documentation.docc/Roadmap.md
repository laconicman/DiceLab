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
- **M9a — Hygiene.** `SCNFloor`→box (the FloorPass spams every frame even
  at `reflectivity = 0`, and the box gives the felt a real UV surface);
  `DiceTable` gains `@MainActor` (discharges TD-9 — a non-isolated
  protocol can't be safely witnessed by actor-isolated classes);
  `TextureResource.init(image:)` replaces the deprecated `generate(from:)`;
  default dice count 3→2 matching the legacy `NumberOfDice` default;
  settings-persistence audit tests. (PR #11)
- **M9b — Camera fit.** Shared engine-free math in `Model/CameraFit.swift`
  (bounding sphere → fit distance from FOV and viewport aspect); damped
  per-frame glide toward one target that flips home↔fitted on a dice-speed
  gate; `fitConverged` latch hands the camera back to orbit once the
  settled pose arrives. Walls became faintly visible glass (legacy was
  `.clear` — fully invisible). Hard-won RealityKit finding: gating
  `realityViewCameraControls` on `isRolling` recreates `RealityView`
  mid-roll and wedges the render graph — the orbit gate must stay static.
  Review also caught: the distance cap must cover the *full* volume
  diagonal (lopsided clusters center the sphere off-origin), the SceneKit
  far plane needed raising past the retreat distance, and `dt` must be
  capped for render pauses. Discharges TD-8, records TD-10. (PR #12)
- **M9c — History panel + sheet anatomy.** `.ultraThinMaterial` panel
  replaces the chip strip: quarter-screen collapsed, tap-to-expand toward
  the safe area, `settings.history` toggle, `rowTint` scaffold for future
  per-player colors. Sheet detents (`.medium`/`.large`) moved onto the
  `.sheet` itself; the editor's preview is pinned above the form — the
  device log's `Picker: invalid selection` spam was also fixed here
  (`Theme.Kind`, a payload-free selection). (PR #13)

- **M9d — Appearance II.** Material controls sealed unless
  `theme.kind == .custom`; per-part emission (face + pip color/intensity —
  the packed texture carries tint ratios, the material scalar carries the
  peak); backdrop channel: procedural equirect presets or a photo via the
  felt's `PhotosPicker` pattern (`FeltImageStore` → `UserImageStore`).
  SceneKit takes the backdrop as `scene.background` +
  `lightingEnvironment`; RealityKit has no scene backdrop — an inside-out
  `UnlitMaterial` dome (`faceCulling = .front`) plus a
  `VirtualEnvironmentProbeComponent` built async from the equirect image.
  Engine findings recorded in Design.md: `EmissiveColor(color:texture:)`
  adds a flat wash — bind `init(texture:)` alone; a photo is LDR, so the
  probe lights without HDR range. Review caught: style picks must retire
  the photo, mid-flight photo imports must not resurrect `.custom`,
  failed conversion must drop the stale probe, the die preview needs the
  same environment, and backdrop rebuilds must dedupe. (PR #15)

## Planned — M9, device-feedback round

Decisions taken with the user after the first device session: camera stays
fitted on the dice after settling; backdrop is presets *plus* a user photo;
emission is a full per-part editor; voice roll is deferred until after the
string catalog exists.

- **M9e — Localization prep.** `.xcstrings` catalog, every user-facing
  string extracted. Voice-roll ("Say roll!") is deliberately deferred —
  mic permission + locale handling is a milestone of its own.

## Next

- Open learning surface: device-time haptic/tuning pass, scripted camera
  moments (would revisit TD-3's default-on toggle), a second skin family,
  or RealityKit-vs-SceneKit performance measurement. Voice-trigger design
  (Speech framework, permissions, per-locale grammar).
