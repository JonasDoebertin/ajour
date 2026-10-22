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
    var openSettings: () -> Void

    static var system: LaunchAtLoginControl {
        LaunchAtLoginControl(
            isEnabled: { LaunchAtLogin.isEnabled },
            setEnabled: LaunchAtLogin.setEnabled,
            openSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }

    static func errorMessage(enabling: Bool) -> String {
        enabling
            ? "Ajour could not be added to your login items. Allow it in System Settings › General › Login Items."
            : "Ajour could not be removed from your login items. Remove it in System Settings › General › Login Items."
    }
}
