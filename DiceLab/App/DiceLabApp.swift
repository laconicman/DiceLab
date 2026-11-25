import SceneKit
import SwiftUI

@main
struct DiceLabApp: App {
    /// Both tables are constructed eagerly — an entity graph and an SCNScene
    /// are cheap until rendered, and keeping both alive preserves per-engine
    /// session state (history, dice) across a switch.
    @State private var sceneKitTable = DiceTableController()
    @State private var realityTable = RealityTableController()

    var body: some Scene {
        WindowGroup {
            WindowRoot(sceneKitTable: sceneKitTable, realityTable: realityTable)
        }
    }
}

/// One instance per WindowGroup window — anything that should be per-window
/// lives here rather than on the shared App struct: `@State` on `App` is
/// vendored once and shared by every window, so a sheet flag there would
/// open in all of them. (Multi-window is off today; the scoping stays right
/// if iPad ever enables it.)
private struct WindowRoot: View {
    let sceneKitTable: DiceTableController
    let realityTable: RealityTableController

    /// Engine choice is app-level state — it decides which controller
    /// instance exists, so it can't live inside one. Same persistence
    /// mechanism (`settings.engine`) the controllers use for their settings.
    @AppStorage(TableSettings.engine) private var engine: DiceEngine = .sceneKit

    /// The sheet hangs off the window root, not the roll screen: an engine
    /// swap destroys the roll screen, and a sheet presented from the dying
    /// view would force-dismiss inside the same transaction that mounts the
    /// new scene view — a TD-10-class render hazard for `RealityView`. The
    /// bonus: settings stay open across a renderer switch, so flipping back
    /// takes one tap.
    @State private var showingSettings = false

    var body: some View {
        Group {
            switch DevFlags.engineOverride ?? engine {
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
        // `dicelab://` — the runtime twin of launch-arg DevFlags, for
        // driving a device build without relaunching (TD-5's device
        // pass needed exactly this). DEBUG only: see DebugURLHandler.
        .modifier(DebugURLHandler(sceneKitTable: sceneKitTable,
                                  realityTable: realityTable,
                                  engine: $engine))
    }

    /// Dev driver: `-appearanceeditor` lands directly in the editor so its
    /// live preview is screenshotable via simctl.
    @ViewBuilder
    private var settingsContent: some View {
        if DevFlags.appearanceEditor {
            NavigationStack {
                switch DevFlags.engineOverride ?? engine {
                case .sceneKit:
                    AppearanceEditor(table: sceneKitTable, preview: sceneKitPreview)
                case .realityKit:
                    AppearanceEditor(table: realityTable, preview: realityPreview)
                }
            }
        } else {
            switch DevFlags.engineOverride ?? engine {
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

/// `dicelab://` dispatch — compiled out of Release builds. An externally
/// openable URL must not mutate persisted settings or the settle ceiling
/// in a build that ships (Devin Review security finding); the scheme
/// itself is also only registered for Debug via `INFOPLIST_FILE` in
/// `project.yml`, so in Release this modifier is a passthrough and no
/// handler exists to receive a URL even if one arrives.
private struct DebugURLHandler: ViewModifier {
    let sceneKitTable: DiceTableController
    let realityTable: RealityTableController
    @Binding var engine: DiceEngine

    func body(content: Content) -> some View {
        #if DEBUG
        content.onOpenURL { url in
            guard let command = DebugURL.command(from: url) else { return }
            DebugURL.perform(command, sceneKit: sceneKitTable,
                             reality: realityTable, engine: $engine)
        }
        #else
        content
        #endif
    }
}
