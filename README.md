# DiceLab

A 3D dice roller for iOS, rebuilt on a modern stack — a learning project.

Descends from [profburke/DiceRollDemo](https://github.com/profburke/DiceRollDemo)
(SceneKit, 2021) and its sibling rewrite `RollingDice`. This is a fresh start:
SwiftUI shell over **two interchangeable engines** — SceneKit (scene graph)
and RealityKit (ECS) — switchable in Settings, the M7 comparison exercise.

## Requirements

- iOS 18+ (the RealityKit engine needs `RealityView`)
- Xcode 27.2+ — `DiceLab.xcodeproj/project.xcproj` is the committed project
  file in Xcode's JSON format (JSON5). Xcode 26 can't open it; 27.0/27.1
  can build it but only 27.2 converts or edits it via `xcrun xcodeproj`.

## Documentation

Direction docs — architecture decisions, the M1–M7 milestone roadmap, and the
tech-debt register — live in `DiceLab/Documentation.docc/` and render via
**Product ▸ Build Documentation** in Xcode. `Design.md` there is authoritative.

## Versioning & releases

Milestone merges get an annotated `v<major>.<sub>` tag — `v1.2` is M12 — and
pushing it runs the release workflow, which asserts the tag matches
`MARKETING_VERSION` and publishes a GitHub release with generated notes.
`MARKETING_VERSION` in `project.xcproj` tracks the latest tag; bump it in the
milestone's closeout commit.

## License

Apache-2.0 — see `LICENSE`. Fresh-authored; carries no code verbatim from the
unlicensed upstream projects (see `TechDebt.md` TD-2).
