import Foundation
import MenuMateCore

struct ManagedService: Identifiable {
    var id: String { item.id }
    let item: ServiceItem
    var enabledInContextMenu: Bool
    let isShortcutBased: Bool   // Shortcuts 型只能隐藏，UI 需标注
    /// (bundleID, message) 在枚举到的全部服务中是否唯一；
    /// 唯一才允许 ServiceStatusEditor 做前后缀模糊匹配（否则会串改兄弟服务）。
    let pairUnique: Bool
}

@MainActor
final class ServicesManager: ObservableObject {
    @Published var services: [ManagedService] = []
    @Published var lastError: String?
    @Published var busy = false

    /// 串行队列：pbs 读写 + ShellRunner（pbs -flush / killall）都是阻塞调用，
    /// 移出主线程避免每次开关冻结 UI；串行保证「写入 → 回读」顺序。
    private static let queue = DispatchQueue(label: "com.menumate.services", qos: .userInitiated)

    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.ServicesMenu.Services.plist")
    }
    private static var backupURL: URL {
        AppPaths.configDirectory().appendingPathComponent("pbs.plist.backup")
    }
    private static var pbsPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/pbs.plist")
    }

    var hasBackup: Bool { FileManager.default.fileExists(atPath: Self.backupURL.path) }

    func reload() {
        busy = true
        Self.queue.async { [weak self] in
            let result = Self.loadServices()
            Task { @MainActor in
                self?.services = result
                self?.busy = false
            }
        }
    }

    func setEnabled(_ enabled: Bool, for service: ManagedService) {
        let item = service.item
        let pairUnique = service.pairUnique
        busy = true
        Self.queue.async { [weak self] in
            Self.backupIfNeeded()
            let defaults = UserDefaults(suiteName: "pbs")
            let status = defaults?.dictionary(forKey: "NSServicesStatus") ?? [:]
            // 唯一性感知匹配 + 就地改值：只动目标服务的条目，
            // 保留 key_equivalent/enabled_services_menu，绝不触碰兄弟服务的键。
            let newStatus = ServiceStatusEditor.apply(
                enabled: enabled, to: status,
                bundleID: item.bundleID, menuTitle: item.menuTitle,
                localizedTitle: item.localizedTitle, message: item.message,
                isPairUnique: pairUnique)
            defaults?.set(newStatus, forKey: "NSServicesStatus")
            let r = ShellRunner.run("/System/Library/CoreServices/pbs", ["-flush"], timeout: 10)
            let error: String? = r.exitCode != 0 ? String(format: String(localized: "runtime.pbsFlushFailed"), r.stderr) : nil
            let result = Self.loadServices()   // 回读校验
            Task { @MainActor in
                if let error { self?.lastError = error }
                self?.services = result
                self?.busy = false
            }
        }
    }

    func restartFinder() {
        Self.queue.async {
            ShellRunner.run("/usr/bin/killall", ["Finder"], timeout: 10)
        }
    }

    func restoreBackup() {
        guard hasBackup else { return }
        busy = true
        Self.queue.async { [weak self] in
            let fm = FileManager.default
            do {
                // 先拷到临时文件再原子替换，避免「删了原文件、拷贝又失败」留下无 pbs.plist 的窗口
                let tmp = Self.pbsPlistURL.deletingLastPathComponent()
                    .appendingPathComponent("pbs.plist.menumate-restore.tmp")
                try? fm.removeItem(at: tmp)
                try fm.copyItem(at: Self.backupURL, to: tmp)
                if fm.fileExists(atPath: Self.pbsPlistURL.path) {
                    _ = try fm.replaceItemAt(Self.pbsPlistURL, withItemAt: tmp)
                } else {
                    try fm.moveItem(at: tmp, to: Self.pbsPlistURL)
                }
            } catch {
                let message = String(format: String(localized: "runtime.restoreBackupFailed"), error.localizedDescription)
                Task { @MainActor in
                    self?.lastError = message
                    self?.busy = false
                }
                return
            }
            // 让 cfprefsd 丢弃缓存后再 flush
            ShellRunner.run("/usr/bin/killall", ["cfprefsd"], timeout: 10)
            ShellRunner.run("/System/Library/CoreServices/pbs", ["-flush"], timeout: 10)
            let result = Self.loadServices()
            Task { @MainActor in
                self?.services = result
                self?.busy = false
            }
        }
    }

    // MARK: - 后台纯逻辑（在 Self.queue 上执行，不触碰 @Published）

    private static func loadServices() -> [ManagedService] {
        var items: [ServiceItem] = []
        if let data = try? Data(contentsOf: cacheURL),
           let parsed = try? ServicesCacheParser.parse(plistData: data) {
            items = parsed
        }
        items += scanWorkflows()
        var seen = Set<String>()
        let deduped = items.filter { seen.insert($0.id).inserted }
        // (bundleID, message) 唯一性：很多服务共享该 pair（Terminal ×2、Instruments ×4、
        // 全部 Automator 快捷操作），非唯一时禁止模糊匹配，否则会串改兄弟服务。
        // 统计范围含非菜单服务，保守起见它们的同 pair 键也可能出现在 status 里。
        var pairCounts: [String: Int] = [:]
        for item in deduped {
            pairCounts[pairKey(item), default: 0] += 1
        }
        let status = UserDefaults(suiteName: "pbs")?.dictionary(forKey: "NSServicesStatus") ?? [:]
        return deduped
            .filter { $0.hasMenuItem }   // 非菜单服务（如 AppleSpell）不展示，避免垃圾 pbs 写入
            .map { item in
                let unique = pairCounts[pairKey(item)] == 1
                let disabled = ServiceStatusEditor.isDisabled(
                    in: status, bundleID: item.bundleID, menuTitle: item.menuTitle,
                    localizedTitle: item.localizedTitle, message: item.message, isPairUnique: unique)
                let shortcutBased = item.bundleID == "com.apple.shortcuts"
                    || item.bundleID == "com.apple.shortcuts.events"
                return ManagedService(item: item, enabledInContextMenu: !disabled,
                                      isShortcutBased: shortcutBased, pairUnique: unique)
            }
            .sorted { $0.item.menuTitle.localizedCompare($1.item.menuTitle) == .orderedAscending }
    }

    private static func pairKey(_ item: ServiceItem) -> String {
        "\(item.bundleID ?? "(null)")\u{1F}\(item.message)"
    }

    private static func scanWorkflows() -> [ServiceItem] {
        let dirs = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services"),
                    URL(fileURLWithPath: "/Library/Services")]
        var result: [ServiceItem] = []
        for dir in dirs {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in names where name.hasSuffix(".workflow") {
                let bundle = dir.appendingPathComponent(name)
                let plist = bundle.appendingPathComponent("Contents/Info.plist")
                if let data = try? Data(contentsOf: plist),
                   let wf = try? WorkflowParser.parse(infoPlistData: data) {
                    result.append(ServiceItem(bundleID: nil, menuTitle: wf.menuTitle,
                                              localizedTitle: nil, message: wf.message,
                                              bundlePath: bundle.path, hasMenuItem: true))
                }
            }
        }
        return result
    }

    private static func backupIfNeeded() {
        guard !FileManager.default.fileExists(atPath: backupURL.path),
              FileManager.default.fileExists(atPath: pbsPlistURL.path) else { return }
        try? FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: pbsPlistURL, to: backupURL)
    }
}
