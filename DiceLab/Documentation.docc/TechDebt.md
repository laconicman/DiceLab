# Tech Debt

Numbered register. `// TODO(TD-n)` markers in code reference these.

| ID | Item | Cost | Discharge |
|---|---|---|---|
| TD-1 | SceneKit is soft-deprecated (iOS 26): patches only, no new features | Platform drift; every new API we adopt elsewhere widens the gap | M7 RealityKit port |
| TD-2 | `profburke/DiceRollDemo` has **no LICENSE** — README promised one, never added | Our port carries no derived code verbatim, but the *design* descends from it; distributing anything closer would need Burke's blessing or a clean-room | Ask author to add a license, or keep derivation at idea level only |
| TD-3 | `.allowsCameraControl` enabled for development | Users can fight scripted camera framing; double-tap camera-switch is an accidental easter egg | M6: settings toggle or tuned `SCNCameraControlConfiguration` |
