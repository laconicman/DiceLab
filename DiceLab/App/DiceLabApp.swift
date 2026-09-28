import SceneKit
import SwiftUI

@main
struct DiceLabApp: App {
    /// Engine choice is app-level state — it decides which controller
    /// instance exists, so it can't live inside one. Same persistence
    /// mechanism (`settings.engine`) the controllers use for their settings.
    @AppStorage(TableSettings.engine) private var engine: DiceEngine = .sceneKit

    /// Both tables are constructed eagerly — an entity graph and an SCNScene
    /// are cheap until rendered, and keeping both alive preserves per-engine
    /// session state (history, dice) across a switch.
    @State private var sceneKitTable = DiceTableController()
    @State private var realityTable = RealityTableController()

    /// The sheet hangs off the window root, not the roll screen: an engine
    /// swap destroys the roll screen, and a sheet presented from the dying
    /// view would force-dismiss inside the same transaction that mounts the
    /// new scene view — a TD-10-class render hazard for `RealityView`. The
    /// bonus: settings stay open across a renderer switch, so flipping back
    /// takes one tap.
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup {
            Group {
                switch engine {
                case .sceneKit:
                    SceneKitRollView(showingSettings: $showingSettings)
                        .environment(sceneKitTable)
                case .realityKit:
                    RealityRollView(showingSettings: $showingSettings)
                        .environment(realityTable)
                }
            }
            .sheet(isPresented: $showingSettings) {
                settingsContent
                    // Detents live on the sheet, not inside SettingsView,
                    // so the dev-flag path gets them too. .medium reads as
                    // a quick toggle panel; .large gives the editor room.
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Dev driver: `-appearanceeditor` lands directly in the editor so its
    /// live preview is screenshotable via simctl.
    @ViewBuilder
    private var settingsContent: some View {
        if DevFlags.appearanceEditor {
            NavigationStack {
                switch engine {
                case .sceneKit:
                    AppearanceEditor(table: sceneKitTable, preview: sceneKitPreview)
                case .realityKit:
                    AppearanceEditor(table: realityTable, preview: realityPreview)
                }
            }
        } else {
            switch engine {
            case .sceneKit:
                SettingsView(table: sceneKitTable, preview: sceneKitPreview)
            case .realityKit:
                SettingsView(table: realityTable, preview: realityPreview)
            }
        }
    }

    /// The appearance editor's live die preview, per engine — built here
    /// rather than inside the roll views because the sheet it serves is
    /// app-level now. Same ownership story as the table worlds: the
    /// controller owns the scene/graph, the view only renders it.
    private var sceneKitPreview: AnyView {
        AnyView(SceneView(
            scene: sceneKitTable.previewScene,
            // The preview's spin is an SCNAction — continuous rendering
            // keeps it animating inside the settings sheet.
            options: [.rendersContinuously],
            antialiasingMode: .multisampling4X))
    }

    private var realityPreview: AnyView {
        AnyView(RealityDiePreview(root: realityTable.previewRoot,
                                  die: realityTable.previewDie))
    }
}
