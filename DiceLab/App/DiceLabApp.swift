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

    var body: some Scene {
        WindowGroup {
            switch engine {
            case .sceneKit:
                SceneKitRollView().environment(sceneKitTable)
            case .realityKit:
                RealityRollView().environment(realityTable)
            }
        }
    }
}
