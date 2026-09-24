# 0001 — SceneKit first, RealityKit later

**Status:** accepted, M0

## Context

Two ancestors exist: `DiceRollDemo` (profburke, 2021) plus our commits on top,
and `RollingDice`, our rewrite of it. Both are SceneKit.

SceneKit is soft-deprecated since iOS 26: security patches only, no new
features. RealityKit is the modern 3D path (ECS, `RealityView`, AR-ready).

## Decision

Build the new app on **SceneKit** anyway, and treat the RealityKit port as its
own later milestone (M7).

## Why

- We inherit working physics tuning (impulse values, rest detection, face-up
  reading). Starting on RealityKit would force re-deriving all of it blind.
- SceneKit's scene-graph + physics API is the gentler on-ramp; the concepts
  (bodies, contacts, impulses) transfer.
- Porting later is the strongest single lesson in the project: it forces us to
  articulate everything SceneKit did implicitly (delegates → Systems, node
  transforms → Transform components, renderer callbacks → per-frame systems).

## Consequence

Nothing we write in M1–M6 should assume SceneKit specifics leak into Model or
the view layer — the port should be able to swap the controller's internals.
