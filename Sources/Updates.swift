import AppKit
import Sparkle

/// Updates via Sparkle, reading the signed appcast attached to the latest GitHub release.
@MainActor
enum Updates {
    private static let userDriverDelegate = UpdateReminders()

    /// Started at launch; Sparkle checks once a day.
    static let updater = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: userDriverDelegate
    )

    static func checkForUpdates() {
        // SoloVolume has no windows of its own, so come forward for Sparkle's.
        NSApp.activate()
        updater.checkForUpdates(nil)
    }
}

/// SoloVolume lives in the menu bar, so let Sparkle remind about updates gently
/// instead of popping a window over whatever you're doing.
private final class UpdateReminders: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
