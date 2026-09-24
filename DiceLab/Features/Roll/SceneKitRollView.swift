import SceneKit
import SwiftUI

/// SceneKit fills the chrome's scene slot: `SceneView` renders the
/// controller-owned `SCNScene`, and the controller doubles as the renderer
/// delegate (per-frame settle check lives there).
struct SceneKitRollView: View {
    @Environment(DiceTableController.self) private var table

    var body: some View {
        RollScreen(table: table, scene: SceneView(
            scene: table.scene,
            options: table.cameraControlEnabled ? [.allowsCameraControl] : [],
            antialiasingMode: .multisampling4X,
            delegate: table
        ))
    }
}
