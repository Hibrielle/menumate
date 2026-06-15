import AppKit
import MenuMateCore

struct ManagedExtension: Identifiable {
    var id: String { info.bundleID }
    let info: FinderExtensionInfo
    let displayName: String
    var stuck: Bool = false   // pluginkit 写入被系统/宿主抢回
}

@MainActor
final class ExtensionManager: ObservableObject {
    @Published var extensions: [ManagedExtension] = []
    static let ownBundleID = "com.menumate.app.FinderExtension"

    /// 串行队列：pluginkit 为阻塞调用（枚举/写入各 10s 超时），
    /// 移出主线程避免每次开关冻结 UI；串行保证「写入 → 回读」顺序。
    private static let queue = DispatchQueue(label: "com.menumate.extensions", qos: .userInitiated)

    func reload() {
        Self.queue.async { [weak self] in
            let result = Self.loadExtensions()
            Task { @MainActor in self?.extensions = result }
        }
    }

    func setEnabled(_ enabled: Bool, for ext: ManagedExtension) {
        let bundleID = ext.info.bundleID
        Self.queue.async { [weak self] in
            ShellRunner.run("/usr/bin/pluginkit",
                            ["-e", enabled ? "use" : "ignore", "-i", bundleID], timeout: 10)
            var result = Self.loadExtensions()
            // 回读校验：pluginkit 可能退出码 0 但状态被抢回（如 OneDrive）
            if let idx = result.firstIndex(where: { $0.id == bundleID }),
               (result[idx].info.election == .use) != enabled {
                result[idx].stuck = true
            }
            Task { @MainActor in self?.extensions = result }
        }
    }

    static func openSystemSettings() {
        // 已验证可用的 deep link（不带未经验证的 extensionPointIdentifier 参数）
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func displayName(forPath path: String) -> String {
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" { return url.deletingPathExtension().lastPathComponent }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // MARK: - 后台纯逻辑（在 Self.queue 上执行，不触碰 @Published）

    private static func loadExtensions() -> [ManagedExtension] {
        let r = ShellRunner.run("/usr/bin/pluginkit", ["-m", "-p", "com.apple.FinderSync", "-v"], timeout: 10)
        return PluginkitParser.parse(r.stdout)
            .filter { $0.bundleID != ownBundleID }
            .map { ManagedExtension(info: $0, displayName: displayName(forPath: $0.path)) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }
}
