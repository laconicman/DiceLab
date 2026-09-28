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
    /// History-panel visibility is chrome, not scene state — same
    /// `@AppStorage` slot class as `speech`.
    @AppStorage(TableSettings.history) private var historyEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Dice") {
                    // Explicit catalog key — the count is a numeric
                    // substitution future locales can pluralize, and an
                    // English-text key would break if the wording moved.
                    Stepper(value: $table.dieCount, in: 1...6) {
                        Text(String(localized: "settings.dieCount",
                                    defaultValue: "Count: \(table.dieCount)",
                                    comment: "Dice-count stepper label"))
                    }
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
                Section {
                    Toggle("Automatic framing", isOn: $table.cameraFitEnabled)
                    Toggle("Camera control", isOn: $table.cameraControlEnabled)
                } header: {
                    Text("Camera")
                } footer: {
                    Text("Automatic framing eases the camera to keep all dice in view while they settle. Camera control lets you orbit freely between rolls.")
                }
                Section {
                    Toggle("Roll history", isOn: $historyEnabled)
                } header: {
                    Text("History")
                } footer: {
                    Text("A session roll list on the table screen — tap its header to expand it toward the safe area.")
                }
                // Last on purpose: the renderer is the deepest cut — the
                // everyday dials sit above it.
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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
