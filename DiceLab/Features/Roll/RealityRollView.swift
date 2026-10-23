import RealityKit
import SwiftUI

/// RealityKit fills the chrome's scene slot. `RealityView`'s content closure
/// runs once — that's where the controller hands over its entity graph and
/// wires event subscriptions. After that the controller mutates entities
/// imperatively, same ownership story as the SceneKit path.
struct RealityRollView: View {
    @Environment(RealityTableController.self) private var table
    @Binding var showingSettings: Bool

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchMagnification: CGFloat = 1

    var body: some View {
        RollScreen(table: table, scene: realityScene,
                   showingSettings: $showingSettings)
    }

    private var realityScene: some View {
        RealityView { content in
            table.populate(&content)
        }
        // Our own orbit (M11), not `.realityViewCameraControls(.orbit)`:
        // the stock control has no floor, pivots on the origin, ignores
        // `cameraTarget`, and keeps a hidden angle that fights any clamp.
        // Attached unconditionally — the handler checks
        // `cameraControlEnabled` and the fit's ownership, so no view-tree
        // branch flips on a setting or a roll (TD-10). Deltas come from
        // `@GestureState`, which SwiftUI resets when a gesture ends *or is
        // cancelled* — a stored baseline would survive a cancelled drag
        // and throw the next one.
        .gesture(DragGesture().updating($dragTranslation) { value, last, _ in
            table.orbit(by: CGSize(width: value.translation.width - last.width,
                                   height: value.translation.height - last.height))
            last = value.translation
        })
        .simultaneousGesture(MagnifyGesture().updating($pinchMagnification) { value, last, _ in
            table.dolly(by: value.magnification / last)
            last = value.magnification
        })
        // The fit's horizontal-FOV math needs the viewport shape.
        .onGeometryChange(for: CGFloat.self) { $0.size.width / $0.size.height }
            action: { table.viewAspect = $0 }
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
