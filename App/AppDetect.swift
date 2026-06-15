// AppDetect.swift — 探测已安装的终端/编辑器,供「通用」里选「默认终端 / 默认编辑器」。
// 选择存 UserDefaults,ActionRunner 注入 MENUMATE_TERMINAL / MENUMATE_EDITOR 环境变量,
// 预设脚本 open-terminal.sh / open-editor.sh 读它决定开哪个(脚本优先,不必改脚本即可切换)。

import AppKit

struct DetectedApp: Identifiable, Hashable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

enum AppDetect {
    // 终端候选(按常见度排序);只列出本机已装的。
    static let terminalCandidates: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "org.alacritty", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "co.zeit.hyper",
    ]
    // 编辑器候选。
    static let editorCandidates: [String] = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",         // VS Code, Cursor
        "com.sublimetext.4", "com.sublimetext.3", "dev.zed.Zed",
        "com.panic.Nova", "com.barebones.bbedit", "com.macromates.TextMate",
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm",
        "com.jetbrains.WebStorm", "com.jetbrains.goland", "com.jetbrains.CLion",
        "com.jetbrains.PhpStorm", "com.jetbrains.rubymine", "com.jetbrains.datagrip",
        "com.jetbrains.rider", "com.google.android.studio",
    ]

    /// 在候选里筛出本机已安装的(名字取自 .app 本体,免硬编)。
    static func installed(_ candidates: [String]) -> [DetectedApp] {
        candidates.compactMap { bid in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return DetectedApp(bundleID: bid, name: name)
        }
    }

    /// 给定 bundleID 的显示名(已装则真实名,否则原样返回 bundleID)。
    static func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}

/// 用户对默认终端/编辑器的偏好(bundle id);空 = 跟随脚本内置默认。
enum AppPrefs {
    private static let terminalKey = "MMPreferredTerminal"
    private static let editorKey = "MMPreferredEditor"

    static var terminalBundleID: String? {
        get { value(terminalKey) }
        set { setValue(terminalKey, newValue) }
    }
    static var editorBundleID: String? {
        get { value(editorKey) }
        set { setValue(editorKey, newValue) }
    }

    private static func value(_ k: String) -> String? {
        let v = UserDefaults.standard.string(forKey: k)
        return (v?.isEmpty == false) ? v : nil
    }
    private static func setValue(_ k: String, _ v: String?) {
        if let v, !v.isEmpty { UserDefaults.standard.set(v, forKey: k) }
        else { UserDefaults.standard.removeObject(forKey: k) }
    }
}
