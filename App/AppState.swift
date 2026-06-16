import Foundation
import MenuMateCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    // ConfigStore 的可变缓存只在主线程访问（本类 @MainActor 持有）
    let store = ConfigStore(directory: AppPaths.configDirectory())
    @Published var config: MenuConfig = MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: [])
    @Published var configError: String?
    /// 扩展包数据层：包动作已并入 config，随快照推送；此处只负责导入/审查/启停/更新/卸载。
    lazy var packManager = PackManager()

    private var heartbeatTimer: Timer?
    private let listener = ActionListener()
    /// 上次推送的快照（值比较，与字典迭代序无关，消除伪差异全量重推）
    private var lastPushed: ExtensionSnapshot?
    /// 心跳计数器：每 10 次无条件全量推一次，收敛残留快照
    private var heartbeatCount: Int = 0
    /// 上次推送时间：snapshotRequest 节流，1s 内忽略重复请求
    private var lastPushTime: Date = .distantPast
    /// 上次由本进程写盘后的 config.json mtime；心跳据此检测"外部进程(AI/CLI/手动)改了 config.json"→ 实时重载
    private var lastConfigMTime: Date = .distantPast

    func start() {
        PresetSeeder.seedIfNeeded()      // 脚本/模板/数据目录落盘（Task 11 实现）
        do {
            config = try store.load()
            configError = nil
        } catch {
            // load() 对缺失文件返回 seed 不抛错，故走到 catch 必是文件存在但解析失败：
            // 保留损坏文件不覆盖，用 seed 跑内存态，错误留给 UI。
            config = .defaultSeed()
            configError = String(format: String(localized: "runtime.configLoadError"), error.localizedDescription)
        }
        // 首启显式落盘 seed：load() 对缺失文件返回 seed 但不写盘，写一份具体文件方便用户查看编辑。
        if configError == nil, !FileManager.default.fileExists(atPath: store.fileURL.path) {
            try? store.save(config)
        }
        // 升级时补进新增的出厂预设（按 presetKey 判定，追加到末尾，保留用户布局与自建动作）。
        if configError == nil, let merged = PresetSeeder.mergeNewPresets(into: config) {
            config = merged
            try? store.save(config)
        }
        migratePresetRenames()
        pruneOrphanIcons()   // 清理上次会话遗留的孤儿图标
        lastConfigMTime = configMTime()  // 基线;之后心跳检测外部改动(让 AI/CLI 直接改 config.json 即时生效)

        packManager.reload()             // 从 Packs/installed.json + config 重建已安装包列表
        startHeartbeat()
        listener.start()
        // 扩展启动（或丢失快照）时会请求一份；节流：1s 内忽略（防 1 条小消息换 N 块广播放大）
        DistributedNotificationCenter.default().addObserver(
            forName: .init(IPC.snapshotRequestNotification), object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                guard Date().timeIntervalSince(AppState.shared.lastPushTime) >= 1 else { return }
                AppState.shared.pushSnapshot()
            }
        }
        pushSnapshot()
    }

    func update(_ newConfig: MenuConfig) {
        config = newConfig
        try? store.save(newConfig)
        lastConfigMTime = configMTime()   // 标记为本进程写入,避免心跳把自己的写当成外部改动而重载
        configError = nil
        pruneOrphanIcons()
        pushSnapshot()
    }

    /// 外部进程(AI / CLI / 手动)改了 config.json 时重读并广播,无需重启 App。
    /// 解析失败(如写到一半)忽略,保留当前内存态,下个心跳再试。
    func reloadFromDisk() {
        guard let loaded = try? store.load() else { return }
        config = loaded
        configError = nil
        lastConfigMTime = configMTime()
        packManager.reload()
        pruneOrphanIcons()
        pushSnapshot()
    }

    private func configMTime() -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }

    /// 一次性正名:open-enclosing 从「前往所在目录」统一为「前往上一层级目录」(只在用户没自行改名时迁移)。
    /// 脚本内容由智能 seeder 自动更新,这里只补配置里存的标题/图标。幂等(改完条件不再命中)。
    private func migratePresetRenames() {
        guard configError == nil else { return }
        var changed = false
        for i in config.actions.indices
        where config.actions[i].presetKey == "open-enclosing" && config.actions[i].title == "前往所在目录" {
            config.actions[i].title = "前往上一层级目录"
            config.actions[i].icon = .symbol("arrow.up")
            changed = true
        }
        if changed { try? store.save(config) }
    }

    /// 清理不再被任何动作引用的自定义图标文件（动作删除 / 换图标 / 放弃导入后的孤儿）。
    private func pruneOrphanIcons() {
        let referenced = Set(config.actions.compactMap { $0.icon.imageFileName })
        IconStore.pruneOrphans(keeping: referenced)
    }

    /// 构造快照（config + 预解析的目录列举）→ 分块逐条推给扩展。
    func pushSnapshot() {
        let snapshot = buildSnapshot()
        lastPushed = snapshot
        lastPushTime = Date()
        guard let encoded = try? snapshot.encodedString() else { return }
        postSnapshot(encoded)
    }

    private func buildSnapshot() -> ExtensionSnapshot {
        let listings = MenuBuilder.prepareListings(config: config, base: AppPaths.configDirectory())
        // 自定义图片图标:把缩放后的 PNG base64 随快照带给扩展(扩展零文件访问)。
        var iconImages: [String: String] = [:]
        for action in config.actions {
            guard let fileName = action.icon.imageFileName,
                  let base64 = IconStore.base64PNG(for: fileName) else { continue }
            iconImages[action.id.uuidString] = base64
        }
        return ExtensionSnapshot(config: config, variantListings: listings, iconImages: iconImages)
    }

    private func postSnapshot(_ encoded: String) {
        for chunk in ChunkedTransport.split(encoded) {
            guard let envelope = try? chunk.encodedString() else { return }
            DistributedNotificationCenter.default().postNotificationName(
                .init(IPC.snapshotNotification), object: envelope, userInfo: nil, deliverImmediately: true)
        }
    }

    /// 心跳 + 按需推快照（模板目录在 App 外被改动时，值比较才会与上次不同）。
    /// 每 10 次无条件全量推一次，收敛残留的伪造快照驻留窗口。
    private func heartbeatTick() {
        DistributedNotificationCenter.default().postNotificationName(
            .init(IPC.heartbeatNotification), object: nil, userInfo: nil, deliverImmediately: true)
        // 外部进程改了 config.json(AI/CLI 直接操作数据源)→ 实时重载 + 重推快照,无需重启。
        if configMTime() > lastConfigMTime { reloadFromDisk(); return }
        heartbeatCount += 1
        let snapshot = buildSnapshot()
        if snapshot != lastPushed || heartbeatCount >= 10 {
            heartbeatCount = 0
            lastPushed = snapshot
            lastPushTime = Date()
            guard let encoded = try? snapshot.encodedString() else { return }
            postSnapshot(encoded)
        }
    }

    private func startHeartbeat() {
        // Timer 闭包非隔离：只做回主线程跳板，状态访问全在 @MainActor 的 heartbeatTick 里
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            DispatchQueue.main.async { AppState.shared.heartbeatTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
        heartbeatTimer = timer
    }
}
