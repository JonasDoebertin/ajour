import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Lets onboarding and settings change launch at login without touching the real login items in tests.
struct LaunchAtLoginControl {
    var isEnabled: () -> Bool
    var setEnabled: (Bool) throws -> Void

    static var system: LaunchAtLoginControl {
        LaunchAtLoginControl(isEnabled: { LaunchAtLogin.isEnabled }, setEnabled: LaunchAtLogin.setEnabled)
    }

    static func errorMessage(for error: any Error) -> String {
        "Could not change launch at login. \(error.localizedDescription)"
    }
}
