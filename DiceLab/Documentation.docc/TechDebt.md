# Tech Debt

Numbered register. `// TODO(TD-n)` markers in code reference these.

| ID | Item | Cost | Discharge |
|---|---|---|---|
| TD-1 | ~~SceneKit is soft-deprecated (iOS 26): patches only, no new features~~ **discharged (M7):** the RealityKit engine ships alongside — the deprecation risk is a settings toggle, not a rewrite | — | — |
| TD-2 | `profburke/DiceRollDemo` has **no LICENSE** — README promised one, never added | Our port carries no derived code verbatim, but the *design* descends from it; distributing anything closer would need Burke's blessing or a clean-room | Ask author to add a license, or keep derivation at idea level only |
| TD-3 | ~~`.allowsCameraControl` enabled for development~~ **discharged (M6):** now a user-facing settings toggle, default on — deliberate for a learning toy; scripted camera framing would revisit it | — | — |
| TD-4 | `FloorPass is not linked to the rendering graph` logged at launch — SceneKit's internal reflection pass on `SCNFloor`, harmless while `reflectivity = 0` | Noise in the console; could mask real warnings | M5: revisit when materials get real work (or drop `SCNFloor` for a box) |
| TD-5 | A die wedged against a wall could stay awake forever, leaving `isRolling` stuck | Rare; UI shows "Rolling…" until it settles or the app restarts | Watch for it on device; add a settle timeout if observed |
| TD-6 | RealityKit impulse/rest tuning is simulator-verified only — meters-scale feel may differ on device | Roll could feel sluggish or settle-check too strict/loose on hardware | Device run: tune `Toss`/`Rest` constants in `RealityTableController` |
| TD-7 | Multi-window: one entity graph is shared — a second window populating the RealityKit view reparents `root` away from the first (entities have a single parent) | Second window shows an empty world | If multi-window ever matters: per-window graphs or a dedicated window model |
