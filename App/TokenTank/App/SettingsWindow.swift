import AppKit
import SwiftUI

/// Opens the Settings window in front of other apps. An accessory (`LSUIElement`)
/// app is not activated by the system, so without the explicit activation the
/// window opens behind the frontmost app.
@MainActor
enum SettingsWindow {
    static func show(_ openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
