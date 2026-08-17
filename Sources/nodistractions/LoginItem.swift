import ServiceManagement

/// Start-at-login registration, wrapped around `SMAppService`.
///
/// Registration follows the app bundle's identity, so it is only offered when
/// the process was launched as the .app — a bare `swift build` binary has no
/// bundle launchd could re-launch at login.
enum LoginItem {
    static var available: Bool { launchedAsApp }

    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS can park a registration in System Settings → Login Items until
    /// the user consents; the toggle shows that as a mixed state.
    static var pending: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(enabled: Bool) throws {
        if enabled {
            if !pending { try SMAppService.mainApp.register() }
            // Registering can land as "waiting for consent" instead of
            // enabled. The approval lives in System Settings, so go there.
            if pending { SMAppService.openSystemSettingsLoginItems() }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var summary: String {
        guard available else { return "unavailable (not running from the app bundle)" }
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "waiting for approval in System Settings → Login Items"
        case .notRegistered: return "disabled"
        case .notFound: return "not found"
        @unknown default: return "unrecognised"
        }
    }
}
