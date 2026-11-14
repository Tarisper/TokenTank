import ServiceManagement

/// Launch-at-login via SMAppService; default is off, the user opts in
/// in Settings (§5 M8). Registered under the app bundle, not the sandboxed path.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// - Parameter enabled: Whether the app should start at login.
    /// - Returns: `false` when the system rejected the change.
    static func setEnabled(_ enabled: Bool) -> Bool {
        var succeeded = true
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            succeeded = false
        }
        return succeeded
    }
}
