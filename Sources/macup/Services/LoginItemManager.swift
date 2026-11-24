import Foundation
import ServiceManagement

@MainActor
@Observable
public final class LoginItemManager {
    public private(set) var isEnabled: Bool = false
    public private(set) var statusDescription: String = ""
    public private(set) var isRunningAsAppBundle: Bool = false

    public init() {
        isRunningAsAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        refresh()
    }

    public func refresh() {
        guard isRunningAsAppBundle else {
            isEnabled = false
            statusDescription = "Build & launch macup.app to enable Launch at Login."
            return
        }

        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            isEnabled = true
            statusDescription = "Enabled — launches automatically when you log in."
        case .requiresApproval:
            isEnabled = false
            statusDescription = "Needs approval in System Settings > General > Login Items."
        case .notRegistered, .notFound:
            isEnabled = false
            statusDescription = "Disabled"
        @unknown default:
            isEnabled = false
            statusDescription = "Unknown status"
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard isRunningAsAppBundle else {
            refresh()
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusDescription = "Failed to update Login Item: \(error.localizedDescription)"
        }
        refresh()
    }
}
