import SwiftUI

/// The settings sheet. Bindings write straight into the `@Observable`
/// controller — `@Bindable` is the bridge, and each write triggers the
/// controller's `didSet` (persist + apply), so the view holds no state.
struct SettingsView: View {
    @Environment(DiceTableController.self) private var table

    var body: some View {
        @Bindable var table = table
        NavigationStack {
            Form {
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
                    Toggle("Haptics", isOn: $table.hapticsEnabled)
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
