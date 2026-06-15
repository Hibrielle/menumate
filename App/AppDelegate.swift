import AppKit
import FinderSync

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorizationOnce()
        Task { @MainActor in AppState.shared.start() }
        if !UserDefaults.standard.bool(forKey: "onboardingDone") || !FIFinderSyncController.isExtensionEnabled {
            Task { @MainActor in OnboardingWindowController.show() }
        }
    }
}
