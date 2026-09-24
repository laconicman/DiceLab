# DiceLab

A 3D dice roller for iOS, rebuilt on a modern stack — a learning project.

Descends from [profburke/DiceRollDemo](https://github.com/profburke/DiceRollDemo)
(SceneKit, 2021) and its sibling rewrite `RollingDice`. This is a fresh start:
SwiftUI shell over **two interchangeable engines** — SceneKit (scene graph)
and RealityKit (ECS) — switchable in Settings, the M7 comparison exercise.

## Requirements

- iOS 18+ (the RealityKit engine needs `RealityView`)

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is
  generated, not committed: run `xcodegen` after cloning or changing
  `project.yml`.

## Documentation

Direction docs — architecture decisions, the M1–M7 milestone roadmap, and the
tech-debt register — live in `DiceLab/Documentation.docc/` and render via
**Product ▸ Build Documentation** in Xcode. `Design.md` there is authoritative.
