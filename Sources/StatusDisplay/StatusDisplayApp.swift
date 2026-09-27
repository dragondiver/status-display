import SwiftUI

struct StatusDisplayApp: App {
    var body: some Scene {
        MenuBarExtra("Status", systemImage: "circle.fill") {
            Button("Beenden") { NSApp.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}
