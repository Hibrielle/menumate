import Foundation
import CryptoKit
import MenuMateCore

enum PresetSeeder {
    /// 启动时对账：把打包的预设脚本同步到 Application Support 的 Scripts/，并准备 Templates/ 与 Data/。
    ///
    /// 脚本同步规则(靠 .shipped.json 侧车记录「我们写过的版本哈希」区分用户改动):
    /// - 盘上没有        → 写入,记录哈希(新装 / 新增预设如 open-parent.sh 即走这条)
    /// - 盘上有且=我们记录 → 若 bundle 更新了则覆盖,刷新哈希(用户没动过的预设随升级自动更新)
    /// - 盘上有但≠我们记录 → 用户改过,保留不动
    /// - 盘上有但无记录(老用户首次升级到本机制):仅当内容与当前 bundle 完全一致时纳入记录基线;
    ///   不一致时无法区分「旧出厂版」还是「用户改过」,一律保留不动(可用「恢复此预设」单条更新)
    static func seedIfNeeded() {
        let fm = FileManager.default
        for dir in [AppPaths.scriptsDirectory(), AppPaths.templatesDirectory(), AppPaths.dataDirectory()] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let scripts = bundledScripts()
        assert(!scripts.isEmpty, "预设脚本未打包进 bundle——检查 project.yml 的 PresetScripts resources 配置")
        if scripts.isEmpty {
            NSLog("MenuMate: 警告——bundle 内无预设脚本，所有预设动作将失效")
        }

        var shipped = loadShipped()
        for url in scripts {
            let name = url.lastPathComponent
            guard let bundledData = try? Data(contentsOf: url) else { continue }
            let bundledHash = sha(bundledData)
            let dest = AppPaths.scriptsDirectory().appendingPathComponent(name)

            if !fm.fileExists(atPath: dest.path) {
                writeScript(from: url, to: dest)
                shipped[name] = bundledHash
                continue
            }
            let onDisk = (try? Data(contentsOf: dest)).map(sha)
            if let recorded = shipped[name] {
                // 用户没动过(盘上=我们记录)且 bundle 有更新 → 覆盖
                if recorded == onDisk, bundledHash != recorded {
                    writeScript(from: url, to: dest)
                    shipped[name] = bundledHash
                }
                // 否则:已是最新,或用户改过(盘上≠记录)→ 保留
            } else if onDisk == bundledHash {
                // 老用户基线:内容恰与当前 bundle 一致 → 纳入记录,后续可随升级自动更新
                shipped[name] = bundledHash
            }
            // else: 老用户且内容不同 → 保留不动
        }
        saveShipped(shipped)

        let templates = AppPaths.templatesDirectory()
        if TemplateStore.list(in: templates).isEmpty {
            fm.createFile(atPath: templates.appendingPathComponent("文本.txt").path, contents: Data())
            fm.createFile(atPath: templates.appendingPathComponent("Markdown.md").path, contents: Data())
        }
    }

    /// 记录「曾经补过/见过的预设 presetKey」,防止用户删掉的预设在下次启动被 mergeNewPresets 又补回来。
    private static let seededKeysDefault = "MMSeededPresetKeys"

    /// 把出厂新增、但用户配置里还没有、且从没补过的预设补进来(按 presetKey 判定;追加到末尾,保留用户布局)。
    /// 「从没补过」用 MMSeededPresetKeys 墓碑判定:用户主动删除的预设留在墓碑里,不会自动回来
    /// (要找回用「恢复出厂预设」)。返回需要写盘的新 config;无新增返回 nil。
    static func mergeNewPresets(into config: MenuConfig) -> MenuConfig? {
        let ud = UserDefaults.standard
        var everSeeded = Set(ud.stringArray(forKey: seededKeysDefault) ?? [])
        let inConfig = Set(config.actions.compactMap(\.presetKey))
        let missing = MenuConfig.defaultSeed().actions.filter {
            guard let key = $0.presetKey else { return false }
            return !inConfig.contains(key) && !everSeeded.contains(key)
        }
        // 基线:凡当前在配置里的预设都标记为已见——首启时这会把全部出厂键纳入墓碑,
        // 使日后删除任意预设都能"粘住"(不被自动补回)。再并入这次新补的键。
        everSeeded.formUnion(inConfig)
        everSeeded.formUnion(missing.compactMap(\.presetKey))
        ud.set(Array(everSeeded), forKey: seededKeysDefault)

        guard !missing.isEmpty else { return nil }
        var config = config
        var order = (config.actions.map(\.sortOrder).max() ?? -1) + 1
        for var action in missing {
            action.sortOrder = order
            order += 1
            config.actions.append(action)
        }
        return config
    }

    /// 恢复出厂:覆盖全部预设脚本 + 重置配置中的预设项(保留用户自建动作)。
    @MainActor
    static func restorePresets(state: AppState) {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppPaths.scriptsDirectory(), withIntermediateDirectories: true)
        var shipped = loadShipped()
        for url in bundledScripts() {
            let dest = AppPaths.scriptsDirectory().appendingPathComponent(url.lastPathComponent)
            writeScript(from: url, to: dest)
            if let data = try? Data(contentsOf: url) { shipped[url.lastPathComponent] = sha(data) }
        }
        saveShipped(shipped)
        var config = state.config
        let custom = config.actions.filter { $0.presetKey == nil }
        config.actions = MenuConfig.defaultSeed().actions + custom
        // 找回被删除的预设:把墓碑重置为全部出厂键(此刻它们都已回到 config)。
        UserDefaults.standard.set(MenuConfig.defaultSeed().actions.compactMap(\.presetKey),
                                  forKey: seededKeysDefault)
        state.update(config)
    }

    /// 恢复单条预设:重新落该预设的出厂脚本 + 把该动作重置为出厂态(保留它当前的位置与启用状态)。
    @MainActor
    static func restorePreset(presetKey: String, state: AppState) {
        guard let fresh = MenuConfig.defaultSeed().actions.first(where: { $0.presetKey == presetKey }) else { return }
        if case .runScript(let spec) = fresh.kind, let rel = spec.scriptPath {
            let name = (rel as NSString).lastPathComponent
            if let src = bundledScripts().first(where: { $0.lastPathComponent == name }) {
                let dest = AppPaths.scriptsDirectory().appendingPathComponent(name)
                writeScript(from: src, to: dest)
                if let data = try? Data(contentsOf: src) {
                    var shipped = loadShipped(); shipped[name] = sha(data); saveShipped(shipped)
                }
            }
        }
        var config = state.config
        guard let idx = config.actions.firstIndex(where: { $0.presetKey == presetKey }) else { return }
        var restored = fresh
        restored.sortOrder = config.actions[idx].sortOrder   // 保留用户排序
        restored.isEnabled = config.actions[idx].isEnabled   // 保留启用/隐藏状态
        config.actions[idx] = restored
        state.update(config)
    }

    static func bundledScripts() -> [URL] {
        Bundle.main.urls(forResourcesWithExtension: "sh", subdirectory: nil) ?? []
    }

    // MARK: - 私有:脚本写入与 .shipped.json 侧车

    private static var shippedURL: URL {
        AppPaths.scriptsDirectory().appendingPathComponent(".shipped.json")
    }

    private static func writeScript(from src: URL, to dest: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dest)
        try? fm.copyItem(at: src, to: dest)
    }

    private static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadShipped() -> [String: String] {
        guard let data = try? Data(contentsOf: shippedURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    private static func saveShipped(_ map: [String: String]) {
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: shippedURL) }
    }
}
