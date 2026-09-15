import Foundation
import MenuMateCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    // ConfigStore 的可变缓存只在主线程访问（本类 @MainActor 持有）
    let store: ConfigStore
    let packTransaction: PackTransaction
    @Published private(set) var storageRecoveryRequired = false
    private var configurationReadable = true

    init(directory: URL = AppPaths.configDirectory(), transaction: PackTransaction? = nil) {
        store = ConfigStore(directory: directory)
        packTransaction = transaction ?? PackTransaction(directory: directory)
    }
    @Published private(set) var config: MenuConfig = MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: [])
    @Published var configError: String?
    /// 设置窗当前 Tab(SettingsWindow 绑定;Hub 可设为 .packs 直接跳到扩展包)
    @Published var settingsTab: SettingsTab = .contextMenu
    /// 扩展包数据层：包动作已并入 config，随快照推送；此处只负责导入/审查/启停/更新/卸载。
    lazy var packManager = PackManager(appState: { [unowned self] in self })

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
    /// 上次重建快照时的模板/图标目录指纹;心跳据此跳过没必要的昂贵重建
    private var lastAuxSignature = ""

    func start() {
        // Recover before seeding, loading config, pruning icons or broadcasting actions.
        do {
            try packTransaction.recover()
            PresetSeeder.seedIfNeeded()
            let loaded = try store.load(fresh: true)
            if !FileManager.default.fileExists(atPath: store.fileURL.path) { try store.save(loaded) }
            config = loaded
            configurationReadable = true
            if let merged = PresetSeeder.mergeNewPresets(into: config), update(merged) {
                PresetSeeder.recordSeededPresets(in: merged)
            } else if configError == nil {
                PresetSeeder.recordSeededPresets(in: config)
            }
            migratePresetRenames()
            if configError == nil { pruneOrphanIcons() }
        } catch {
            storageRecoveryRequired = packTransaction.needsRecovery
            configurationReadable = false
            // A corrupt file or unfinished recovery must never activate seed actions or GC icons.
            configError = String(format: String(localized: "runtime.configLoadError"), error.localizedDescription)
        }
        lastConfigMTime = configMTime()

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

    /// Publish only after persistence succeeds. Failed edits leave the last saved config active.
    @discardableResult func update(_ newConfig: MenuConfig) -> Bool {
        do {
            let baseline = config
            try prepareForMutation()
            guard baseline == config else { throw PackTransaction.Failure.configurationChanged }
            try store.save(newConfig, expected: baseline)
            acceptPersisted(newConfig)
            return true
        } catch {
            reportSaveFailure(error)
            return false
        }
    }

    @discardableResult func mutateConfig(_ change: (inout MenuConfig) -> Void) -> Bool {
        do {
            try prepareForMutation()
            var candidate = config
            change(&candidate)
            try store.save(candidate, expected: config)
            acceptPersisted(candidate)
            return true
        } catch {
            reportSaveFailure(error)
            return false
        }
    }

    /// PackManager calls this before building a candidate, then commits all three resources together.
    func prepareForMutation() throws {
        do {
            let recovered = try packTransaction.recover()
            let loaded = try store.load(fresh: true)
            if recovered || !configurationReadable || loaded != config {
                configurationReadable = true
                storageRecoveryRequired = false
                config = loaded
                lastConfigMTime = configMTime()
                packManager.reload()
            }
        } catch {
            configurationReadable = false
            storageRecoveryRequired = packTransaction.needsRecovery
            throw error
        }
    }

    func commitPack(key: String, replacement: URL?, candidate: MenuConfig, installed: Data, expectedInstalled: Data?) throws {
        do {
            try packTransaction.apply(key: key, replacement: replacement, config: candidate,
                                      installed: installed, expectedConfig: config, expectedInstalled: expectedInstalled)
            acceptPersisted(candidate)
        } catch {
            reportSaveFailure(error)
            throw error
        }
    }

    private func acceptPersisted(_ saved: MenuConfig) {
        config = saved
        configurationReadable = true
        storageRecoveryRequired = false
        configError = nil
        lastConfigMTime = configMTime()
        pruneOrphanIcons()
        pushSnapshot()
    }

    private func reportSaveFailure(_ error: Error) {
        storageRecoveryRequired = packTransaction.needsRecovery
        configError = String(format: String(localized: "runtime.configSaveError"), error.localizedDescription)
        if storageRecoveryRequired { pushSnapshot() }
    }

    /// Also serves as the explicit retry action after a failed recovery/load.
    func reloadFromDisk() {
        do {
            try packTransaction.recover()
            let loaded = try store.load(fresh: true)
            acceptPersisted(loaded)
            packManager.reload()
        } catch {
            storageRecoveryRequired = packTransaction.needsRecovery
            configurationReadable = false
            configError = String(format: String(localized: "runtime.configLoadError"), error.localizedDescription)
        }
    }

    private func configMTime() -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }

    /// 一次性正名:open-enclosing 从「前往所在目录」统一为「前往上一层级目录」(只在用户没自行改名时迁移)。
    /// 脚本内容由智能 seeder 自动更新,这里只补配置里存的标题/图标。幂等(改完条件不再命中)。
    private func migratePresetRenames() {
        guard configError == nil else { return }
        var candidate = config
        var changed = false
        for i in candidate.actions.indices
        where candidate.actions[i].presetKey == "open-enclosing" && candidate.actions[i].title == "前往所在目录" {
            candidate.actions[i].title = "前往上一层级目录"
            candidate.actions[i].icon = .symbol("arrow.up")
            changed = true
        }
        if changed { _ = update(candidate) }
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
        if storageRecoveryRequired {
            return ExtensionSnapshot(config: MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: []), variantListings: [:])
        }
        let listings = MenuBuilder.prepareListings(config: config, base: AppPaths.configDirectory())
        // 自定义图片图标:把缩放后的 PNG base64 随快照带给扩展(扩展零文件访问)。
        var iconImages: [String: String] = [:]
        for action in config.actions {
            guard let fileName = action.icon.imageFileName,
                  let base64 = IconStore.base64PNG(for: fileName) else { continue }
            iconImages[action.id.uuidString] = base64
        }
        return ExtensionSnapshot(config: config, variantListings: listings, iconImages: iconImages, language: LocalizedText.language)
    }

    private func postSnapshot(_ encoded: String) {
        for chunk in ChunkedTransport.split(encoded) {
            guard let envelope = try? chunk.encodedString() else { return }
            DistributedNotificationCenter.default().postNotificationName(
                .init(IPC.snapshotNotification), object: envelope, userInfo: nil, deliverImmediately: true)
        }
    }

    /// 心跳 + 按需推快照。buildSnapshot 含目录 I/O + 逐图标读盘 + 编码,不必每 3s 都做:
    /// config 变动由上面的 mtime 分支即时处理;此处只在【模板/图标目录】变化或每 10 拍兜底时重建。
    private func heartbeatTick() {
        DistributedNotificationCenter.default().postNotificationName(
            .init(IPC.heartbeatNotification), object: nil, userInfo: nil, deliverImmediately: true)
        // 外部进程改了 config.json(AI/CLI 直接操作数据源)→ 实时重载 + 重推快照,无需重启。
        if storageRecoveryRequired || !configurationReadable || configMTime() != lastConfigMTime { reloadFromDisk(); return }
        heartbeatCount += 1
        // 廉价门控:模板/图标目录没变且未到兜底拍,就跳过昂贵的快照重建。
        let sig = auxMTimeSignature()
        if sig == lastAuxSignature && heartbeatCount < 10 { return }
        lastAuxSignature = sig
        let snapshot = buildSnapshot()
        if snapshot != lastPushed || heartbeatCount >= 10 {
            heartbeatCount = 0
            lastPushed = snapshot
            lastPushTime = Date()
            guard let encoded = try? snapshot.encodedString() else { return }
            postSnapshot(encoded)
        }
    }

    /// 快照中【非 config】部分的来源:模板目录(变体列举)与图标目录(自定义图标字节)。
    /// 取两者的修改时间做廉价指纹;变了才需要重建快照。
    private func auxMTimeSignature() -> String {
        let base = AppPaths.configDirectory()
        func mtime(_ sub: String) -> String {
            let p = base.appendingPathComponent(sub).path
            let d = (try? FileManager.default.attributesOfItem(atPath: p)[.modificationDate]) as? Date
            return d.map { String($0.timeIntervalSince1970) } ?? "-"
        }
        return mtime("Templates") + "|" + mtime("Icons")
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
