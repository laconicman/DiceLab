import PhotosUI
import SwiftUI

/// The appearance editor — the `CubeMaterialSettings` surface modernized:
/// theme presets plus custom die/felt colors, finish sliders, a felt photo,
/// and a lighting preset, with a live 3D die preview supplied by whichever
/// engine is active.
///
/// Editing semantics follow the legacy app: a preset fills the fields, and
/// touching any field flips the theme to `.custom` carrying a full copy —
/// the `appearance` binding below performs that flip on every write.
struct AppearanceEditor<Table: DiceTable>: View {
    @Bindable var table: Table
    /// The live preview widget — an `AnyView` because each engine builds
    /// its own (`SceneView` vs `RealityView`); the editor doesn't care.
    let preview: AnyView

    @State private var photoItem: PhotosPickerItem?

    /// Writes through to `theme = .custom(...)`: presets are read-only
    /// templates, editing makes the theme custom automatically.
    private var appearance: Binding<Appearance> {
        Binding(get: { table.theme.appearance },
                set: { table.theme = .custom($0) })
    }

    var body: some View {
        Form {
            Section {
                preview
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())
            }
            Section("Theme") {
                Picker("Preset", selection: $table.theme) {
                    Text("Ivory").tag(Theme.ivory)
                    Text("Onyx").tag(Theme.onyx)
                    // Selecting Custom snapshots the current fields — the
                    // appearance binding then edits inside it.
                    Text("Custom").tag(Theme.custom(table.theme.appearance))
                }
            }
            Section("Die") {
                ColorPicker("Face", selection: color(appearance.die.faceColor))
                ColorPicker("Pips", selection: color(appearance.die.pipColor))
                sliderRow("Roughness", appearance.die.roughness)
                sliderRow("Metalness", appearance.die.metalness)
                sliderRow("Clearcoat", appearance.die.clearcoat)
            }
            Section("Table") {
                ColorPicker("Felt color", selection: color(appearance.felt.color))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Use photo as felt", systemImage: "photo")
                }
                if appearance.wrappedValue.felt.usesImage {
                    Button("Remove photo", role: .destructive) {
                        FeltImageStore.clear()
                        appearance.wrappedValue.felt.usesImage = false
                    }
                }
                Picker("Lighting", selection: appearance.lighting) {
                    ForEach(LightingPreset.allCases, id: \.self) {
                        Text($0.rawValue.capitalized).tag($0)
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                FeltImageStore.save(image)
                appearance.wrappedValue.felt.usesImage = true
            }
        }
    }

    /// `Binding<CodableColor>` → `Binding<Color>` — the model stores plain
    /// RGBA; the picker speaks `SwiftUI.Color`. Every write flips to custom
    /// via the `appearance` binding's setter.
    private func color(_ binding: Binding<CodableColor>) -> Binding<Color> {
        Binding(get: { binding.wrappedValue.color },
                set: { binding.wrappedValue = CodableColor($0) })
    }

    private func sliderRow(_ title: String,
                           _ binding: Binding<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: binding, in: 0...1)
                .frame(maxWidth: 200)
        }
    }
}
