import SceneKit
import SwiftUI

/// SceneKit fills the chrome's scene slot: `SceneView` renders the
/// controller-owned `SCNScene`, and the controller doubles as the renderer
/// delegate (per-frame settle check lives there).
struct SceneKitRollView: View {
    @Environment(DiceTableController.self) private var table
    @Binding var showingSettings: Bool

    var body: some View {
        RollScreen(table: table, scene: SceneView(
            scene: table.scene,
            // Static on purpose: flipping this option mid-roll rebuilds
            // the view, and the RealityKit twin wedges its render graph on
            // that. Ownership is instead time-sliced by the fit itself —
            // it stops writing once the settled pose converges.
            options: table.cameraControlEnabled ? [.allowsCameraControl] : [],
            antialiasingMode: .multisampling4X,
            delegate: table
        )
        // The fit's horizontal-FOV math needs the viewport shape.
        .onGeometryChange(for: CGFloat.self) { $0.size.width / $0.size.height }
            action: { table.viewAspect = $0 },
        showingSettings: $showingSettings)
    }
}
