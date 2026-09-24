# 0002 — SceneView + controller-owned SCNScene

**Status:** accepted, M1

## Context

A SwiftUI app can host SceneKit two ways:

- **`SceneView`** — SwiftUI's native bridge (iOS 15+). Takes the `SCNScene`,
  options, an `SCNSceneRendererDelegate`, antialiasing. Declarative, but only
  exposes what Apple wrapped.
- **`UIViewRepresentable`** around `SCNView` — full control (custom gestures,
  `SCNView`-only properties, overlay SKScene), at the cost of writing the
  representable boilerplate.

## Decision

`SceneView` for now; keep `UIViewRepresentable` in the pocket.

The `SCNScene` is owned by `DiceTableController` (an `@Observable` class held in
`@State` at the app root), never by a view.

## Why

- Everything we need — scene injection, renderer delegate (M3 rest detection),
  camera control, antialiasing — is already on `SceneView`.
- A view struct is recreated every render pass; a scene owns mutable physics
  state that must persist. Owning it in the controller makes the imperative
  world a dependency the view layer binds to, not holds.
- If a later milestone needs something `SceneView` doesn't expose (e.g. a
  custom `SCNView` gesture), the representable swap touches only `RollView`.
