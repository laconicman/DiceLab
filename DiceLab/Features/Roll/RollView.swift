import SceneKit
import SwiftUI

/// The dice table screen: the 3D scene with app chrome layered over it.
struct RollView: View {
    @Environment(DiceTableController.self) private var table

    var body: some View {
        SceneView(
            scene: table.scene,
            options: [.allowsCameraControl],
            antialiasingMode: .multisampling4X
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Button("Roll", action: table.roll)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 32)
        }
    }
}

#Preview {
    RollView()
        .environment(DiceTableController())
}
