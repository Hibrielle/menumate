import FinderSync
import AppKit
import MenuMateCore

class FinderSync: FIFinderSync {
    /// 扩展零文件访问：菜单数据（config + 预解析目录列举）由主 App 经分布式通知推送，
    /// 进程内仅存内存。这是消除 macOS 14/15「访问其他 App 数据」弹窗的架构前提。
    private var snapshot: ExtensionSnapshot?
    private let reassembler = ChunkReassembler()   // queue: .main 串行投递 → 单线程使用
    private var lastHeartbeat = Date.distantPast
    private var lastLaunchAttempt = Date.distantPast
    // representedObject 不能跨 Finder 进程边界存活，改用 tag(整数,可序列化)映射载荷。
    // 每次 menu(for:) 重建，点击紧随其后，故最新一份映射即为点击所对应的菜单。
    private var pendingRequests: [Int: String] = [:]
    private var nextTag = 1

    override init() {
        super.init()
        var dirs: Set<URL> = [URL(fileURLWithPath: "/")]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        volumes.forEach { dirs.insert($0) }
        FIFinderSyncController.default().directoryURLs = dirs

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
            if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                FIFinderSyncController.default().directoryURLs.insert(url)
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .init(IPC.heartbeatNotification), object: nil, queue: .main) { [weak self] _ in
            self?.lastHeartbeat = Date()
        }
        DistributedNotificationCenter.default().addObserver(
            // object: nil 有意为之——DNC 发送方不可信，防御靠块/总量上限+解码；
            // 伪造快照最多改菜单外观，点击派发仍被主 App 的本地配置闸门拦截
            forName: .init(IPC.snapshotNotification), object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let s = note.object as? String, s.utf8.count <= 64 * 1024,
                  let chunk = try? ChunkedTransport.Chunk.decode(s),
                  let payload = self.reassembler.receive(chunk),
                  let snap = try? ExtensionSnapshot.decode(payload) else { return }
            self.snapshot = snap
        }
        requestSnapshot()   // 扩展启动晚于主 App 推送时，主动要一份
    }

    private func requestSnapshot() {
        DistributedNotificationCenter.default().postNotificationName(
            .init(IPC.snapshotRequestNotification), object: "request", userInfo: nil,
            deliverImmediately: true)
    }

    // MARK: - 菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return nil
        }
        guard Date().timeIntervalSince(lastHeartbeat) < 10 else {
            return singleItemMenu(title: String(localized: "ext.launchMenuMate"))
        }
        guard let snap = snapshot else {
            requestSnapshot()   // 主 App 在跑（心跳新鲜）但快照未达：催一份，下次右键即可用
            return singleItemMenu(title: String(localized: "ext.loadingMenu"), enabled: false)
        }
        let context: MatchContext
        if menuKind == .contextualMenuForContainer {
            guard let target = FIFinderSyncController.default().targetedURL() else { return nil }
            context = .container(target)
        } else {
            let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
            guard !urls.isEmpty else { return nil }
            // 选中项过多时载荷会超限被主 App 丢弃，与其静默失败不如明确告知
            guard urls.count <= IPC.maxPaths else {
                return singleItemMenu(
                    title: String(format: String(localized: "ext.tooManyItems"), IPC.maxPaths),
                    enabled: false)
            }
            context = .items(urls)
        }
        let input = MenuBuildInput(config: snap.config, context: context, heartbeatFresh: true,
                                   variantListings: snap.variantListings)
        let specs = MenuBuilder.build(input)
        guard !specs.isEmpty else { return nil }
        pendingRequests.removeAll()
        nextTag = 1
        let menu = NSMenu(title: "")
        specs.forEach { menu.addItem(makeItem($0, context: context, iconImages: snap.iconImages)) }
        return menu
    }

    private func singleItemMenu(title: String, enabled: Bool = true) -> NSMenu {
        let menu = NSMenu(title: "")
        let item = NSMenuItem(title: title,
                              action: enabled ? #selector(launchMainApp(_:)) : nil,
                              keyEquivalent: "")
        item.target = enabled ? self : nil
        menu.addItem(item)
        return menu
    }

    private func makeItem(_ spec: MenuItemSpec, context: MatchContext,
                          iconImages: [String: String]) -> NSMenuItem {
        let hasAction = spec.request != nil
        let item = NSMenuItem(title: spec.title,
                              action: hasAction ? #selector(menuItemClicked(_:)) : nil,
                              keyEquivalent: "")
        item.target = hasAction ? self : nil
        // 自定义图片图标优先:用快照携带的 base64(PNG) 字节画(扩展零文件访问)。
        if let actionID = spec.request?.actionID,
           let base64 = iconImages[actionID.uuidString],
           let data = Data(base64Encoded: base64),
           let image = NSImage(data: data) {
            image.size = NSSize(width: 16, height: 16)   // 菜单图标尺寸
            item.image = image
        } else if let symbol = spec.symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if var request = spec.request {
            request.paths = contextPaths(context)
            if let payload = try? request.encodedString() {
                let tag = nextTag
                nextTag += 1
                item.tag = tag
                pendingRequests[tag] = payload   // tag 跨进程存活，representedObject 不存活
            }
        }
        if !spec.children.isEmpty {
            let sub = NSMenu(title: spec.title)
            spec.children.forEach { sub.addItem(makeItem($0, context: context, iconImages: iconImages)) }
            item.submenu = sub
        }
        return item
    }

    private func contextPaths(_ context: MatchContext) -> [String] {
        switch context {
        case .items(let urls): return urls.map(\.path)
        case .container(let url): return [url.path]
        }
    }

    // MARK: - 动作

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let payload = pendingRequests[sender.tag] else { return }
        // 载荷一律分块发送（小载荷即单块），任何尺寸都不落盘
        for chunk in ChunkedTransport.split(payload) {
            guard let envelope = try? chunk.encodedString() else { return }
            DistributedNotificationCenter.default().postNotificationName(
                .init(IPC.actionNotification), object: envelope, userInfo: nil, deliverImmediately: true)
        }
    }

    @objc private func launchMainApp(_ sender: Any?) {
        guard Date().timeIntervalSince(lastLaunchAttempt) > 60 else { return }
        lastLaunchAttempt = Date()
        // appex 位于 MenuMate.app/Contents/PlugIns/FinderExtension.appex → 上溯 3 级
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard appURL.pathExtension == "app" else { return }
        NSWorkspace.shared.openApplication(at: appURL,
                                           configuration: NSWorkspace.OpenConfiguration(),
                                           completionHandler: nil)
    }
}
