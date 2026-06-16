import AppKit
import MenuMateCore

struct DuplicateGroup: Identifiable {
    let id: String        // bundleID
    let copies: [URL]
}

@MainActor
final class OpenWithCleaner: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var scanning = false
    @Published var unregisterSupported = true

    static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    /// 红线：绝不调用 lsregister -kill（macOS 26 已移除；15 上有损坏 System Settings 实证）
    /// lsregister -h 可能阻塞数秒，移出主线程。
    func probe() {
        let path = Self.lsregisterPath
        Task.detached {
            let r = ShellRunner.run(path, ["-h"], timeout: 10)
            let supported = (r.stdout + r.stderr).contains("-u")
            await MainActor.run { [weak self] in self?.unregisterSupported = supported }
        }
    }

    func scan() {
        scanning = true
        Task.detached { [weak self] in
            let r = ShellRunner.run("/usr/bin/mdfind",
                                    ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 60)
            var byBundleID: [String: Set<URL>] = [:]
            for line in r.stdout.split(separator: "\n") {
                let url = URL(fileURLWithPath: String(line))
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      Self.appearsInOpenWith(bundle, at: url) else { continue }
                byBundleID[id, default: []].insert(url)
            }
            let result = byBundleID.compactMap { id, urls -> DuplicateGroup? in
                urls.count > 1 ? DuplicateGroup(id: id, copies: urls.sorted { $0.path < $1.path }) : nil
            }.sorted { $0.id < $1.id }
            await MainActor.run { [weak self] in
                self?.groups = result
                self?.scanning = false
            }
        }
    }

    /// 只保留"会出现在『打开方式』菜单里"的 App,即:
    ///   ① 声明了可打开文档(CFBundleDocumentTypes 非空)——后台 agent / 安装器 / 构建产物
    ///      不声明文档类型,永远不进「打开方式」,过滤掉(避免列出 logioptionsplus_agent 这类噪音);
    ///   ② 不是嵌套在别的 .app 内部的捆绑 helper。
    private static func appearsInOpenWith(_ bundle: Bundle, at url: URL) -> Bool {
        let docTypes = bundle.infoDictionary?["CFBundleDocumentTypes"] as? [Any] ?? []
        guard !docTypes.isEmpty else { return false }
        if url.deletingLastPathComponent().path.contains(".app/") { return false }
        return true
    }

    /// 反注册单个副本（lsregister -u 可能耗时数秒，移出主线程）。
    /// Spotlight 重新索引后可能恢复，UI 提示配合移入废纸篓。
    func unregister(_ url: URL) async -> Bool {
        guard unregisterSupported else { return false }
        let path = Self.lsregisterPath
        return await Task.detached {
            ShellRunner.run(path, ["-u", url.path], timeout: 30).exitCode == 0
        }.value
    }

    func trash(_ url: URL) -> Bool {
        (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }
}
