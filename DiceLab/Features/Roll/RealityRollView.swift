import RealityKit
import SwiftUI

/// RealityKit fills the chrome's scene slot. `RealityView`'s content closure
/// runs once — that's where the controller hands over its entity graph and
/// wires event subscriptions. After that the controller mutates entities
/// imperatively, same ownership story as the SceneKit path.
struct RealityRollView: View {
    @Environment(RealityTableController.self) private var table
    @Binding var showingSettings: Bool

    var body: some View {
        RollScreen(table: table, scene: realityScene,
                   showingSettings: $showingSettings)
    }

    @ViewBuilder
    private var realityScene: some View {
        let view = RealityView { content in
            table.populate(&content)
        }
        // Orbit gestures when the setting is on; no modifier when off —
        // `CameraControls` isn't an OptionSet, so there's no `.none` to
        // pass. The gate must NOT key on `isRolling`: flipping the branch
        // rebuilds `RealityView`, and a mid-roll rebuild wedges the render
        // graph (framebuffer errors, blank view). Fit/orbit ownership is
        // time-sliced inside the controller instead (`fitConverged`).
        if table.cameraControlEnabled {
            aspectFeed(view.realityViewCameraControls(.orbit))
        } else {
            aspectFeed(view)
        }
    }

    /// The fit's horizontal-FOV math needs the viewport shape — applied
    /// via a helper because the orbit-gated and plain branches are
    /// different view types.
    private func aspectFeed(_ content: some View) -> some View {
        content.onGeometryChange(for: CGFloat.self) {
            $0.size.width / $0.size.height
        } action: { table.viewAspect = $0 }
    }
}

/// The appearance editor's live preview: the controller-owned preview
/// world rendered by a second, smaller `RealityView`. The spin runs on
/// `SceneEvents.Update` — the ECS analog of the SceneKit preview's
/// `SCNAction`, scoped to this view's lifetime via `@State`. File-level
/// because the sheet it lives in now hangs off the app root.
struct RealityDiePreview: View {
    let root: Entity
    let die: ModelEntity?
    @State private var spinSub: EventSubscription?

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(root)
            spinSub = content.subscribe(to: SceneEvents.Update.self) { event in
                die?.transform.rotation *= simd_quatf(
                    angle: Float(event.deltaTime) * 1.4,
                    axis: simd_normalize(SIMD3<Float>(0.6, 0.8, 0)))
            }
        }
    }
}
