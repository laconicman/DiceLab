import RealityKit
import SwiftUI

/// RealityKit fills the chrome's scene slot. `RealityView`'s content closure
/// runs once — that's where the controller hands over its entity graph and
/// wires event subscriptions. After that the controller mutates entities
/// imperatively, same ownership story as the SceneKit path.
struct RealityRollView: View {
    @Environment(RealityTableController.self) private var table

    var body: some View {
        RollScreen(table: table, scene: realityScene,
                   preview: AnyView(DiePreview(root: table.previewRoot,
                                               die: table.previewDie)))
    }

    /// The appearance editor's live preview: the controller-owned preview
    /// world rendered by a second, smaller `RealityView`. The spin runs on
    /// `SceneEvents.Update` — the ECS analog of the SceneKit preview's
    /// `SCNAction`, scoped to this view's lifetime via `@State`.
    private struct DiePreview: View {
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

    @ViewBuilder
    private var realityScene: some View {
        let view = RealityView { content in
            table.populate(&content)
        }
        // Orbit gestures when the setting is on; no modifier when off —
        // `CameraControls` isn't an OptionSet, so there's no `.none` to pass.
        if table.cameraControlEnabled {
            view.realityViewCameraControls(.orbit)
        } else {
            view
        }
    }
}
