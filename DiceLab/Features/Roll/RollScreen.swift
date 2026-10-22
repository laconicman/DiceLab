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
    /// The settings sheet's visibility — bound, not owned: the sheet itself
    /// hangs off the app root so an engine swap can't force-dismiss it
    /// mid-transaction (and so settings stay open across a renderer switch).
    @Binding var showingSettings: Bool
    @Environment(\.scenePhase) private var scenePhase
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
                if DevFlags.appearanceEditor || DevFlags.settings {
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
                    // A runtime-built `String` renders verbatim — the
                    // explicit key is what keeps the catalog reachable.
                    Text(String(localized: "roll.total",
                                defaultValue: "\(roll.total)",
                                comment: "Result banner — the settled roll's total"))
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
                    // Full width so the Roll button centers on the screen
                    // — not on the widest child. Without it the stack hugs
                    // the history panel's width when present and the
                    // button's own when not, shifting it off-center.
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottom)
                    .padding(.bottom, 32)
                }
            }
            // Shake-to-roll: an invisible first responder, because SwiftUI has
            // no shake gesture — see ShakeDetector.
            .background(ShakeDetector(onShake: table.roll))
    }
}
