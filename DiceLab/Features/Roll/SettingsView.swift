import SwiftUI

/// The settings sheet. Bindings write straight into the `@Observable`
/// controller — `@Bindable` is the bridge, and each write triggers the
/// controller's `didSet` (persist + apply), so the view holds no state.
///
/// The engine is the exception: it selects *which* controller exists, so it
/// can't live on a controller. It reads/writes the same `settings.engine`
/// key the app root reads — `@AppStorage` is the shared slot.
struct SettingsView<Table: DiceTable>: View {
    @Bindable var table: Table
    /// The live die preview — engine views build it (`SceneView` or
    /// `RealityView`); the settings sheet just hosts it.
    let preview: AnyView
    @AppStorage(TableSettings.engine) private var engine: DiceEngine = .sceneKit
    /// Speech is view-layer feedback, so its toggle is `@AppStorage` like
    /// `engine` — see `TableSettings.speech`.
    @AppStorage(TableSettings.speech) private var speechEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Renderer", selection: $engine) {
                        ForEach(DiceEngine.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                } header: {
                    Text("Engine")
                } footer: {
                    Text("SceneKit: scene graph. RealityKit: entity-component-system — same table, two architectures.")
                }
                Section("Dice") {
                    Stepper("Count: \(table.dieCount)",
                            value: $table.dieCount, in: 1...6)
                    NavigationLink {
                        AppearanceEditor(table: table, preview: preview)
                    } label: {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                }
                Section("Feedback") {
                    // Two channels, two toggles: hardware without a Taptic
                    // Engine can still play the knock, and a user may want
                    // sound without taps (or vice versa).
                    Toggle("Haptics", isOn: $table.hapticsEnabled)
                    Toggle("Sound", isOn: $table.soundEnabled)
                    Toggle("Speak results", isOn: $speechEnabled)
                }
                Section("Debug") {
                    Toggle("Camera control", isOn: $table.cameraControlEnabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
