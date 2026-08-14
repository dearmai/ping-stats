import Foundation
import ServiceManagement

/// Login-item registration. `SMAppService` owns the state, so nothing here is
/// mirrored into `PingSettings` — the toggle always reads back from the system.
@MainActor
enum LaunchAtLogin {
    /// `SMAppService.mainApp` needs a real `.app` bundle with an identifier; under
    /// bare `swift run` the executable has neither and registration always fails.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        isSupported && SMAppService.mainApp.status == .enabled
    }

    /// True when registration succeeded but the user still has to allow the item
    /// in System Settings > General > Login Items.
    static var requiresApproval: Bool {
        isSupported && SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isSupported else { throw LaunchAtLoginError.unsupported }
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LaunchAtLoginError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: L10n.string("Launch at login needs the packaged PingStats.app bundle.")
        }
    }
}
