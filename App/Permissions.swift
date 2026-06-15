// Permissions.swift — 一次性把 MenuMate 需要的系统权限申请掉(在首次引导里预请求,使用前就授权)。
//
// macOS 的 TCC 对每类权限只问一次:授权后永久生效、永不再弹;拒绝后也不再自动弹,
// 需用户去「系统设置」改。所以这里的目标是"在使用前主动触发那一次弹窗",而不是反复请求。
// 涉及三类:
//   - 通知:脚本失败提醒(UNUserNotificationCenter)。
//   - 自动化 › Finder:「前往上一层/所在目录」在 Finder 内同窗导航(发 Apple Event)。
//   - 辅助功能:在浏览器上传/打开对话框里发 ⌘↑ 上一层(合成按键)。
//
// 开发期注意:ad-hoc 签名每次重编 cdhash 变化,TCC 会"忘记"授权而重新弹;
// 用稳定签名(Apple Development / Developer ID)后即可一次授权跨版本保留。

import AppKit
import ApplicationServices
import UserNotifications

enum Permissions {
    // MARK: 辅助功能

    /// 当前是否已被授予辅助功能(可读,实时)。
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// 触发辅助功能授权:未授权时弹系统框(含"打开系统设置"),并把 MenuMate 加入列表。已授权则直接返回 true。
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 自动化(Finder + System Events)

    /// 向 Finder 与 System Events 各发一个无害 Apple Event,触发一次性「MenuMate 想要控制 X」授权框。
    /// 导航脚本运行期就是用 osascript 控制这两者(Finder 同窗导航 / System Events 发 ⌘↑),
    /// 故这里也用 osascript 子进程预约,保证授权主体(MenuMate)与运行期完全一致。
    /// 每次 executeAndReturnError 同步阻塞等用户回应,故放后台线程顺序触发。
    static func primeAutomation() {
        DispatchQueue.global(qos: .userInitiated).async {
            runOsascript("tell application \"Finder\" to return name")
            runOsascript("tell application \"System Events\" to return name")
        }
    }

    private static func runOsascript(_ source: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        try? p.run()
        p.waitUntilExit()
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: 通知

    static func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    // MARK: 一键预请求

    /// 在使用前一次性触发全部权限弹窗(供首次引导调用)。
    static func primeAll() {
        requestNotifications()
        primeAutomation()
        requestAccessibility()
    }
}
