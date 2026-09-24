import SwiftUI

@main
struct DiceLabApp: App {
    @State private var table = DiceTableController()

    var body: some Scene {
        WindowGroup {
            RollView()
                .environment(table)
        }
    }
}
