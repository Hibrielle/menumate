import SwiftUI
import Sparkle
import MenuMateCore

@main
struct MenuMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    // Sparkle 自动更新:appcast 与公钥见 Info.plist(SUFeedURL / SUPublicEDKey),发布流程见 docs/RELEASING.md。
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        // 菜单栏下拉 — 对照 docs/design/hifi/screen-misc.jsx MenuBar(系统右键菜单外观)。
        // 用系统原生 MenuBarExtra,项与分隔结构对齐设计稿。
        MenuBarExtra("MenuMate", systemImage: "contextualmenu.and.cursorarrow") {
            Button(String(localized: "menubar.openSettings")) {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(String(localized: "menubar.recentRuns")) {
                openWindow(id: "log")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button(String(localized: "menubar.checkForUpdates")) { updater.checkForUpdates(nil) }
            Divider()
            Button(String(localized: "menubar.restartFinder")) { ShellRunner.run("/usr/bin/killall", ["Finder"], timeout: 10) }
            Divider()
            Button(String(localized: "menubar.quit")) { NSApp.terminate(nil) }
        }
        Window(String(localized: "menubar.settingsWindowTitle"), id: "settings") { SettingsWindow() }
        Window(String(localized: "menubar.logWindowTitle"), id: "log") {
            ExecutionLogView()
        }
        .defaultSize(width: 420, height: 340)
    }
}
