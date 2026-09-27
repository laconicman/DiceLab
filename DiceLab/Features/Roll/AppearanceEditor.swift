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
    /// Same stale-event guard as the controllers' rollID: an async import
    /// must not outlive the selection that started it. itemIdentifier can't
    /// serve — identifier-less items all compare equal (nil == nil).
    @State private var importGeneration = 0
    /// The backdrop channel gets its own picker state — one counter per
    /// channel, so a felt import in flight can't cancel a backdrop pick.
    @State private var backdropItem: PhotosPickerItem?
    @State private var backdropImportGeneration = 0

    /// Writes through to `theme = .custom(...)`: presets are read-only
    /// templates, editing makes the theme custom automatically.
    private var appearance: Binding<Appearance> {
        Binding(get: { table.theme.appearance },
                set: { table.theme = .custom($0) })
    }

    /// The picker binds the payload-free `Kind` — a `.custom` selection
    /// stays selected no matter how the fields mutate under it.
    private var themeKind: Binding<Theme.Kind> {
        Binding(get: { table.theme.kind },
                set: { kind in
                    switch kind {
                    case .ivory: table.theme = .ivory
                    case .onyx: table.theme = .onyx
                    // Selecting Custom snapshots the current fields.
                    case .custom: table.theme = .custom(table.theme.appearance)
                    }
                })
    }

    var body: some View {
        // The preview is pinned above the scrollable form — at the sheet's
        // medium detent an in-form row scrolls away, and editing blind
        // defeats the point of a live preview.
        VStack(spacing: 0) {
            preview
                .frame(height: 140)
            Form {
                Section {
                    Picker("Preset", selection: themeKind) {
                        Text("Ivory").tag(Theme.Kind.ivory)
                        Text("Onyx").tag(Theme.Kind.onyx)
                        Text("Custom").tag(Theme.Kind.custom)
                    }
                } header: {
                    Text("Theme")
                } footer: {
                    // M9d: presets are sealed looks — the dials only exist
                    // under .custom, so a slider can't silently mutate
                    // "Ivory". Choosing Custom snapshots the preset's
                    // fields, and *then* editing is safe.
                    if table.theme.kind != .custom {
                        Text("Presets are sealed looks — choose Custom to edit materials.")
                    }
                }
                if table.theme.kind == .custom {
                    Section("Die") {
                        ColorPicker("Face", selection: color(appearance.die.faceColor))
                        ColorPicker("Pips", selection: color(appearance.die.pipColor))
                        sliderRow("Roughness", appearance.die.roughness)
                        sliderRow("Metalness", appearance.die.metalness)
                        sliderRow("Clearcoat", appearance.die.clearcoat)
                    }
                    Section("Emission") {
                        ColorPicker("Face glow",
                                    selection: color(appearance.die.emission.faceColor))
                        sliderRow("Face intensity",
                                  appearance.die.emission.faceIntensity,
                                  in: 0...EmissionAppearance.maxIntensity)
                        ColorPicker("Pip glow",
                                    selection: color(appearance.die.emission.pipColor))
                        sliderRow("Pip intensity",
                                  appearance.die.emission.pipIntensity,
                                  in: 0...EmissionAppearance.maxIntensity)
                    }
                    Section("Table") {
                        ColorPicker("Felt color", selection: color(appearance.felt.color))
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Use photo as felt", systemImage: "photo")
                        }
                        if appearance.wrappedValue.felt.usesImage {
                            Button("Remove photo", role: .destructive) {
                                // Clear the selection first — an in-flight import
                                // checks it and must not resurrect the removed file.
                                photoItem = nil
                                importGeneration += 1
                                UserImageStore.felt.clear()
                                var next = appearance.wrappedValue
                                next.felt.usesImage = false
                                appearance.wrappedValue = next
                            }
                        }
                        Picker("Lighting", selection: appearance.lighting) {
                            ForEach(LightingPreset.allCases, id: \.self) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                    }
                    Section {
                        Picker("Style", selection: backdropPreset) {
                            ForEach(BackdropPreset.allCases, id: \.self) {
                                Text($0.rawValue.capitalized).tag($0)
                            }
                        }
                        PhotosPicker(selection: $backdropItem, matching: .images) {
                            Label("Use photo as backdrop", systemImage: "photo")
                        }
                        if appearance.wrappedValue.backdrop.usesImage {
                            Button("Remove backdrop photo", role: .destructive) {
                                backdropItem = nil
                                backdropImportGeneration += 1
                                UserImageStore.backdrop.clear()
                                var next = appearance.wrappedValue
                                next.backdrop.usesImage = false
                                appearance.wrappedValue = next
                            }
                        }
                    } header: {
                        Text("Backdrop")
                    } footer: {
                        Text("The backdrop doubles as the scene's light source where the engine supports image-based lighting.")
                    }
                }
            }
        }
        .navigationTitle("Appearance")
        .onChange(of: photoItem) { _, item in
            importGeneration += 1
            let generation = importGeneration
            importPhoto(item, into: .felt, isCurrent: { generation == importGeneration }) {
                $0.felt.usesImage = true
                $0.felt.revision += 1
            }
        }
        .onChange(of: backdropItem) { _, item in
            backdropImportGeneration += 1
            let generation = backdropImportGeneration
            importPhoto(item, into: .backdrop,
                        isCurrent: { generation == backdropImportGeneration }) {
                $0.backdrop.usesImage = true
                $0.backdrop.revision += 1
            }
        }
    }

    /// Style and photo are exclusive: picking a style retires the photo,
    /// or "None" could never remove a visible backdrop. The file stays on
    /// disk — re-picking the photo is the explicit way back.
    private var backdropPreset: Binding<BackdropPreset> {
        Binding(get: { appearance.wrappedValue.backdrop.preset },
                set: { preset in
                    var next = appearance.wrappedValue
                    next.backdrop.preset = preset
                    next.backdrop.usesImage = false
                    appearance.wrappedValue = next
                })
    }

    /// A picked photo goes to disk via its store, then one write flips
    /// `usesImage` + bumps `revision` — a replaced photo differs only by
    /// revision, and two writes would re-materialize the table twice for
    /// one pick. `isCurrent` is the stale-load guard: a Remove or a newer
    /// pick while the load was in flight must win. The `kind` check covers
    /// the other stale case — a preset picked mid-load sealed the theme,
    /// and the landing write must not resurrect `.custom`.
    private func importPhoto(_ item: PhotosPickerItem?,
                             into store: UserImageStore,
                             isCurrent: @escaping () -> Bool,
                             update: @escaping (inout Appearance) -> Void) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            guard isCurrent(), table.theme.kind == .custom else { return }
            store.save(image)
            var next = appearance.wrappedValue
            update(&next)
            appearance.wrappedValue = next
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
                           _ binding: Binding<Double>,
                           in range: ClosedRange<Double> = 0...1) -> some View {
        LabeledContent(title) {
            Slider(value: binding, in: range)
                .frame(maxWidth: 200)
        }
    }
}
