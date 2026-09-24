import SceneKit
import SwiftUI

/// The dice table screen: the 3D scene with app chrome layered over it.
struct RollView: View {
    @Environment(DiceTableController.self) private var table

    var body: some View {
        SceneView(
            scene: table.scene,
            options: [.allowsCameraControl],
            antialiasingMode: .multisampling4X,
            delegate: table
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if let roll = table.lastRoll {
                Text(roll.faces.map(String.init).joined(separator: " + ")
                     + " = \(roll.total)")
                    .font(.title2.monospacedDigit().bold())
                    .padding(8)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            Button(table.isRolling ? "Rolling…" : "Roll", action: table.roll)
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
