import RealityKit
import SwiftUI

/// RealityKit fills the chrome's scene slot. `RealityView`'s content closure
/// runs once — that's where the controller hands over its entity graph and
/// wires event subscriptions. After that the controller mutates entities
/// imperatively, same ownership story as the SceneKit path.
struct RealityRollView: View {
    @Environment(RealityTableController.self) private var table

    var body: some View {
        RollScreen(table: table, scene: realityScene)
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
