import SceneKit
import SwiftUI

/// SceneKit fills the chrome's scene slot: `SceneView` renders the
/// controller-owned `SCNScene`, and the controller doubles as the renderer
/// delegate (per-frame settle check lives there).
struct SceneKitRollView: View {
    @Environment(DiceTableController.self) private var table
    @Binding var showingSettings: Bool

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchMagnification: CGFloat = 1

    var body: some View {
        RollScreen(table: table, scene: sceneContent,
                   showingSettings: $showingSettings)
    }

    private var sceneContent: some View {
        SceneView(
            scene: table.scene,
            // No `.allowsCameraControl`: measured on PavP, SwiftUI's
            // `SceneView` gesture path takes the camera to elev −79°
            // regardless of `SCNCameraController.minimumVerticalAngle`
            // (M11 shipped this limit; it did nothing on device). Our
            // own orbit mirrors the RealityKit twin — same math, same
            // feel, same floor.
            options: [],
            antialiasingMode: .multisampling4X,
            delegate: table
        )
        // Deltas via `@GestureState`'s `updating`: SwiftUI resets it
        // when a gesture ends *or is cancelled* — a controller-side
        // baseline would survive a cancelled drag and throw the next.
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
