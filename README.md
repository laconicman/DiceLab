# DiceLab

A 3D dice roller for iOS, rebuilt on a modern stack — a learning project.

Descends from [profburke/DiceRollDemo](https://github.com/profburke/DiceRollDemo)
(SceneKit, 2021) and its sibling rewrite `RollingDice`. This is a fresh start:
SwiftUI shell, SceneKit physics, RealityKit port planned as a later milestone.

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is
  generated, not committed: run `xcodegen` after cloning or changing
  `project.yml`.

## Roadmap

- [x] M1 — SwiftUI shell: `SceneView` + controller-owned scene
- [ ] M2 — physics: dice, walls, floor, impulses
- [ ] M3 — rest detection + face-up reading (`simd`), first tests
- [ ] M4 — Core Haptics + collision audio
- [ ] M5 — materials, lighting, face textures, shader modifier
- [ ] M6 — app features: dice count, shake-to-roll, history
- [ ] M7 — RealityKit port

Why each choice was made is logged in `docs/decisions/`.
