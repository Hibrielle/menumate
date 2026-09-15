import SwiftUI
import Sparkle
import MenuMateCore

@main
struct MenuMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    // Sparkle 自动更新:appcast 与公钥见 Info.plist(SUFeedURL / SUPublicEDKey),发布流程见 docs/RELEASING.md。
    private static var updaterConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else { return false }
        return true
    }
    private let updater = SPUStandardUpdaterController(startingUpdater: Self.updaterConfigured, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        // 菜单栏下拉 — 对照 docs/design/hifi/screen-misc.jsx MenuBar(系统右键菜单外观)。
        // 用系统原生 MenuBarExtra,项与分隔结构对齐设计稿。
        MenuBarExtra {
            Button(String(localized: "menubar.openSettings")) {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(String(localized: "menubar.recentRuns")) {
                openWindow(id: "log")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(String(localized: "menubar.checkForUpdates")) { updater.checkForUpdates(nil) }
                .disabled(Self.updaterConfigured == false)
            Divider()
            Button(String(localized: "menubar.restartFinder")) { ShellRunner.run("/usr/bin/killall", ["Finder"], timeout: 10) }
            Divider()
            Button(String(localized: "menubar.quit")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "contextualmenu.and.cursorarrow")
                .accessibilityLabel("MenuMate")
                .onReceive(NotificationCenter.default.publisher(for: AppDelegate.showSettingsNotification)) { _ in
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        Window(String(localized: "menubar.settingsWindowTitle"), id: "settings") { SettingsWindow() }
        Window(String(localized: "menubar.logWindowTitle"), id: "log") {
            ExecutionLogView()
        }
        .defaultSize(width: 540, height: 480)
    }
}
