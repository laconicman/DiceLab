import SwiftUI

/// The dice table screen's chrome: result banner, settings gear, history
/// strip, roll button, shake detection — everything *except* the 3D scene
/// widget, which arrives as `scene` so either engine can fill the slot.
///
/// Generic over `Table: DiceTable`: observation works through the plain
/// stored property because `@Observable` registers property reads inside
/// `body` — no `@Environment` wrapper needed when the caller already has
/// the object.
struct RollScreen<Table: DiceTable, SceneContent: View>: View {
    let table: Table
    let scene: SceneContent
    /// The appearance editor's live die preview — each engine builds its
    /// own (`SceneView`/`RealityView`); the chrome only hosts it.
    let preview: AnyView
    @Environment(\.scenePhase) private var scenePhase
    /// Transient UI state — the correct home for `@State`: its lifetime
    /// *should* match this view's, unlike the world (the Q2 lesson applied).
    @State private var showingSettings = false
    /// Speech service — `@State` because it must outlive view rebuilds
    /// (synthesizer state), same discipline as the controllers' ownership.
    @State private var speech = SpeechController()
    /// View-layer setting for view-layer feedback — `@AppStorage`, same
    /// slot the settings sheet writes.
    @AppStorage(TableSettings.speech) private var speechEnabled = true
    /// Same class as `speech`: chrome visibility, not scene state.
    @AppStorage(TableSettings.history) private var historyEnabled = true

    var body: some View {
        scene
            .ignoresSafeArea()
            // The haptic engine is suspended on backgrounding and never
            // resumes on its own — restart it when the app returns.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { table.sceneActivated() }
            }
            .onAppear {
                table.sceneActivated()
                // Dev driver: `xcrun simctl launch … -autoroll` exercises
                // throw → settle → publish without manual tapping.
                if DevFlags.autoroll {
                    table.roll()
                }
                if DevFlags.appearanceEditor {
                    showingSettings = true
                }
            }
            // Speech rides the published result, not the physics — the view
            // observes `lastRoll`, so the trigger is engine-free and the
            // controllers never hear about AVSpeechSynthesizer.
            // Keyed on `id`: RollResult equality compares faces, and two
            // identical rolls are still two announcements.
            .onChange(of: table.lastRoll?.id) { _, _ in
                guard speechEnabled, let roll = table.lastRoll else { return }
                speech.speak(roll)
            }
            .onChange(of: speechEnabled) { _, enabled in
                if !enabled { speech.stop() }
            }
            .overlay(alignment: .top) {
                if let roll = table.lastRoll {
                    // An equation needs an explicit catalog key — a joined
                    // `String` would render verbatim and extract nothing.
                    Text(String(localized: "roll.equation",
                                defaultValue: "\(roll.faces.map(String.init).joined(separator: " + ")) = \(roll.total)",
                                comment: "Result banner — faces joined by ' + ', then the total"))
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
                .accessibilityLabel("Settings")
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            .overlay(alignment: .bottom) {
                // The panel's caps are fractions of the screen — the
                // reader is scoped to this overlay and pinned bottom so
                // it measures the screen without reshaping the layout.
                GeometryReader { geo in
                    VStack(spacing: 12) {
                        // M9c: the optional session record — collapsed to
                        // a quarter of the screen, expandable up to just
                        // under the result banner (banner ~50 + button
                        // row ~60 + padding ≈ 160 reserved).
                        if historyEnabled, !table.history.isEmpty {
                            HistoryPanel(
                                rolls: table.history,
                                collapsedHeight: geo.size.height / 4,
                                expandedHeight: geo.size.height
                                    - geo.safeAreaInsets.top - 160)
                                .padding(.horizontal, 12)
                        }
                        Button(table.isRolling ? "Rolling…" : "Roll", action: table.roll)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 32)
                }
            }
            // Shake-to-roll: an invisible first responder, because SwiftUI has
            // no shake gesture — see ShakeDetector.
            .background(ShakeDetector(onShake: table.roll))
            .sheet(isPresented: $showingSettings) {
                // Dev driver: `-appearanceeditor` lands directly in the
                // editor so its live preview is screenshotable via simctl.
                Group {
                    if DevFlags.appearanceEditor {
                        NavigationStack {
                            AppearanceEditor(table: table, preview: preview)
                        }
                    } else {
                        SettingsView(table: table, preview: preview)
                    }
                }
                // Detents live on the sheet, not inside SettingsView, so
                // the dev-flag path gets them too. .medium reads as a
                // quick toggle panel; .large gives the editor room.
                .presentationDetents([.medium, .large])
            }
    }
}
