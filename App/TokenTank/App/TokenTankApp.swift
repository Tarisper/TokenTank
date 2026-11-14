import AppKit
import SwiftUI
import TokenTankKit

struct TokenTankApp: App {
    @Environment(\.openSettings) private var openSettings
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("TokenTank", systemImage: "fuelpump") {
            MenuBarView()
                .environmentObject(model)
                .onOpenURL { url in
                    if let route = URLRouter.route(for: url) {
                        model.route = route
                        SettingsWindow.show(openSettings)
                    }
                }
        }
        Settings {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}
