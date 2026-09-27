import StatusCore
import SwiftUI

struct StatusDisplayApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: StatusIcon.image(color: model.status.preset.color, waiting: model.hasWaitingAgent))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
