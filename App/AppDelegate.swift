import AppKit
import FinderSync
import MenuMateCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let extensionBundleID = "com.menumate.app.FinderExtension"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorizationOnce()
        Task { @MainActor in AppState.shared.start() }

        let onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        let enabled = Self.extensionEnabled()
        if !onboardingDone || !enabled {
            Task { @MainActor in OnboardingWindowController.show() }
        }
    }

    /// 扩展是否启用。FIFinderSyncController.isExtensionEnabled 在开发/ad-hoc 签名版上不可靠
    /// (常返回 false 即便扩展已启用、右键正常)→ 用 pluginkit 这个「Finder 真正加载哪个」的实况兜底。
    static func extensionEnabled() -> Bool {
        let api = FIFinderSyncController.isExtensionEnabled
        let pk = ShellRunner.run("/usr/bin/pluginkit", ["-m", "-i", extensionBundleID], timeout: 5)
        // pluginkit -m 输出行首:`+` 启用 / `-` 停用 / `!` 异常;空=未注册。
        let pkEnabled = pk.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+")
        NSLog("[MenuMate][onboarding] isExtensionEnabled=\(api) pluginkit=\(pkEnabled) onboardingDone=\(UserDefaults.standard.bool(forKey: "onboardingDone")) pkRaw=\(pk.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        return api || pkEnabled
    }
}
