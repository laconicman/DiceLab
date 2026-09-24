import SceneKit
import SwiftUI

/// The dice table screen: the 3D scene with app chrome layered over it.
struct RollView: View {
    @Environment(DiceTableController.self) private var table
    @Environment(\.scenePhase) private var scenePhase
    /// Transient UI state — the correct home for `@State`: its lifetime
    /// *should* match this view's, unlike the scene (the Q2 lesson applied).
    @State private var showingSettings = false

    var body: some View {
        SceneView(
            scene: table.scene,
            options: table.cameraControlEnabled ? [.allowsCameraControl] : [],
            antialiasingMode: .multisampling4X,
            delegate: table
        )
        .ignoresSafeArea()
        // The haptic engine is suspended on backgrounding and never resumes
        // on its own — restart it each time the app returns to active.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { table.sceneActivated() }
        }
        .onAppear { table.sceneActivated() }
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
        .overlay(alignment: .topTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .padding(10)
                    .background(.regularMaterial, in: .circle)
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 16) {
                // Session history: last five settled rolls, newest first.
                if !table.history.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(table.history.suffix(5).reversed()) { roll in
                            Text(roll.faces.map(String.init).joined(separator: "+")
                                 + "=\(roll.total)")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: .capsule)
                        }
                    }
                }
                Button(table.isRolling ? "Rolling…" : "Roll", action: table.roll)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(.bottom, 32)
        }
        // Shake-to-roll: an invisible first responder, because SwiftUI has
        // no shake gesture — see ShakeDetector.
        .background(ShakeDetector(onShake: table.roll))
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

#Preview {
    RollView()
        .environment(DiceTableController())
}
