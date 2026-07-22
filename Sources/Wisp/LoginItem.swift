import Foundation
import ServiceManagement

/// Launch-at-login, via `SMAppService` — no helper bundle and no login-item
/// plist, just a registration keyed off the app bundle itself.
///
/// The real state lives in the system database rather than Wisp's settings
/// file: the user can also flip it in System Settings › General › Login Items,
/// and that has to win.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True if the toggle can work at all. Registration needs a real, signed
    /// `.app` bundle, so it silently does nothing for a bare `swift run`
    /// binary — better to disable the control than to show one that lies.
    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Returns the resulting state, which is the caller's cue to re-sync the UI
    /// if the request failed.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else { return false }
        do {
            if enabled {
                // Registering while already enabled throws, which is harmless
                // but noisy; skip it.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Wisp: login item \(enabled ? "register" : "unregister") failed: \(error)")
        }
        return isEnabled
    }
}
