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
    @AppStorage(TableSettings.engine) private var engine: DiceEngine = .sceneKit

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
                    Picker("Skin", selection: $table.skin) {
                        ForEach(DieSkin.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                }
                Section("Feel") {
                    // One feedback channel: the toggle gates haptics *and*
                    // the audio knock (they're events in the same pattern),
                    // so the label says what it actually silences.
                    Toggle("Haptics & sound", isOn: $table.hapticsEnabled)
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
