import Foundation
import MenuMateCore

// MARK: - Public value types

/// 已安装扩展包的视图模型(由 installed.json + config 派生)。
struct InstalledPack: Identifiable, Equatable {
    var id: String { key }
    let key: String              // 安装目录名(owner-repo sanitize)
    let manifest: PackManifest
    let repoURL: String          // 克隆用完整 URL
    let repo: String             // owner/repo 显示
    let commitSHA: String        // 短 SHA
    let enabledCount: Int        // config 中 packID==key 且 isEnabled 的动作数
    let totalCount: Int          // config 中 packID==key 的动作数
}

/// `clone` 的产物:已克隆到临时目录、解析+校验过的包,附每个动作脚本源码供审查。
/// 此阶段绝不执行任何脚本。
struct ClonedPack {
    let tempDir: URL
    let key: String
    let manifest: PackManifest
    let repoURL: String
    let repo: String             // owner/repo
    let commitSHA: String        // 短 SHA
    let scripts: [String: String]   // PackAction.id → 脚本源码(读不到则缺省)
    var extraFiles: [PackFile] = []  // manifest 未声明、需审查的文件(隐藏脚本/可执行/二进制)
}

/// `checkUpdate` 结果:远端 HEAD 与本地 commitSHA 不同。
struct PackUpdateAvailable: Equatable {
    let key: String
    let currentSHA: String
    let remoteSHA: String
}

/// `cloneUpdate` 的产物:新克隆 + 与本地的逐文件 diff(本期为「按文件给出 old/new 全文 + 变更统计」)。
struct PackUpdate {
    let key: String
    let tempDir: URL
    let newManifest: PackManifest
    let newSHA: String
    let newRepoURL: String
    let newRepo: String
    let diffsByFile: [FileDiff]      // 脚本(相对路径)的新旧全文,UI 端渲染逐行
    let newScripts: [String: String] // 新动作脚本源码(审查用)

    struct FileDiff: Equatable {
        let path: String         // 相对仓库根
        let oldText: String?     // nil = 远端新增
        let newText: String?     // nil = 远端删除
        var isAdded: Bool { oldText == nil && newText != nil }
        var isRemoved: Bool { newText == nil && oldText != nil }
        var isModified: Bool { oldText != nil && newText != nil && oldText != newText }
        var isUnchanged: Bool { oldText == newText }
    }
}

// MARK: - PackManager

@MainActor
final class PackManager: ObservableObject {
    @Published private(set) var packs: [InstalledPack] = []

    /// 注入点:默认用全局 AppState 单例,测试可替换。
    /// 默认参数避免引用 @MainActor 的 AppState.shared(默认参数在非隔离上下文求值);
    /// 传 nil 时由 appState() 在 @MainActor 调用点惰性解析。
    private let appStateOverride: (() -> AppState)?
    init(appState: (() -> AppState)? = nil) {
        self.appStateOverride = appState
    }
    private func appState() -> AppState { appStateOverride?() ?? AppState.shared }

    enum PackError: LocalizedError {
        case gitFailed(String)
        case noManifest
        case manifestInvalid(String)
        case packNotInstalled(String)
        case notAGitRepo

        var errorDescription: String? {
            switch self {
            case .gitFailed(let m): return String(format: String(localized: "packs.errorGit"), m)
            case .noManifest: return String(localized: "packs.errorNoManifest")
            case .manifestInvalid(let m): return String(format: String(localized: "packs.errorManifest"), m)
            case .packNotInstalled(let k): return String(format: String(localized: "packs.errorPackNotFound"), k)
            case .notAGitRepo: return String(localized: "packs.errorNotAGitRepo")
            }
        }
    }

    // MARK: Paths

    private static var packsRoot: URL {
        AppPaths.configDirectory().appendingPathComponent("Packs", isDirectory: true)
    }
    private static var installedFile: URL {
        packsRoot.appendingPathComponent("installed.json")
    }
    private static func packDir(_ key: String) -> URL {
        packsRoot.appendingPathComponent(key, isDirectory: true)
    }

    // MARK: - Reload (rebuild `packs` from installed.json + config)

    func reload() {
        let records = Self.loadInstalled()
        let actions = appState().config.actions
        packs = records.map { rec in
            let mine = actions.filter { $0.packID == rec.key }
            return InstalledPack(
                key: rec.key, manifest: rec.manifest, repoURL: rec.repoURL,
                repo: rec.repo, commitSHA: rec.commitSHA,
                enabledCount: mine.filter(\.isEnabled).count,
                totalCount: mine.count)
        }
        .sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    // MARK: - Import: step 1 — clone (NEVER executes scripts)

    func clone(_ urlOrShorthand: String) async throws -> ClonedPack {
        let repoURL = Self.normalizeRepoURL(urlOrShorthand)
        let repo = Self.repoDisplay(from: repoURL)
        let key = Self.sanitizeKey(repo)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("menumate-pack-\(UUID().uuidString)", isDirectory: true)

        // git clone --depth 1 — pure fetch, no script execution.
        let clone = await Self.git(["clone", "--depth", "1", repoURL, tempDir.path], cwd: nil)
        guard clone.exitCode == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            throw PackError.gitFailed(clone.stderr.isEmpty ? clone.stdout : clone.stderr)
        }

        do {
            let (manifest, scripts) = try Self.readManifestAndScripts(in: tempDir)
            // 安全网:列出 manifest 之外的文件(脚本可经相对路径 source 它们),逼审查者看见隐藏的兄弟文件。
            let extras = PackInspector.undeclaredFiles(inDirectory: tempDir,
                                                       declared: Set(manifest.actions.map(\.script)))
            let sha = await Self.shortHEAD(in: tempDir)
            return ClonedPack(tempDir: tempDir, key: key, manifest: manifest,
                              repoURL: repoURL, repo: repo, commitSHA: sha,
                              scripts: scripts, extraFiles: extras)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    // MARK: - Import: step 2 — confirm (move into place, inject DISABLED actions)

    func confirmImport(_ cloned: ClonedPack) throws {
        let fm = FileManager.default
        let dest = Self.packDir(cloned.key)

        // Move tempDir → Packs/<key>/ (replace if a stale dir exists).
        try fm.createDirectory(at: Self.packsRoot, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: cloned.tempDir, to: dest)

        // Inject actions into config — ALL disabled by default.
        var config = appState().config
        let baseOrder = (config.actions.map(\.sortOrder).max() ?? -1) + 1
        let newActions = cloned.manifest.actions.enumerated().map { offset, pa in
            Self.menuAction(from: pa, packKey: cloned.key, repo: cloned.repo,
                            packDir: dest, sortOrder: baseOrder + offset)
        }
        config.actions.append(contentsOf: newActions)

        // Persist installed.json BEFORE update() so reload() sees the record.
        var records = Self.loadInstalled().filter { $0.key != cloned.key }
        records.append(InstalledRecord(key: cloned.key, repoURL: cloned.repoURL,
                                       repo: cloned.repo, commitSHA: cloned.commitSHA,
                                       manifest: cloned.manifest))
        try Self.saveInstalled(records)

        appState().update(config)
        reload()
    }

    // MARK: - Enable / disable a single pack action

    func setActionEnabled(_ enabled: Bool, actionID: UUID) {
        var config = appState().config
        guard let idx = config.actions.firstIndex(where: { $0.id == actionID }),
              config.actions[idx].packID != nil else { return }
        guard config.actions[idx].isEnabled != enabled else { return }
        config.actions[idx].isEnabled = enabled
        appState().update(config)
        reload()
    }

    // MARK: - Uninstall

    func uninstall(_ key: String) throws {
        var config = appState().config
        config.actions.removeAll { $0.packID == key }
        appState().update(config)

        let dir = Self.packDir(key)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }

        let records = Self.loadInstalled().filter { $0.key != key }
        try Self.saveInstalled(records)
        reload()
    }

    // MARK: - Update: check (compare remote HEAD SHA vs local)

    func checkUpdate(_ key: String) async -> PackUpdateAvailable? {
        guard let rec = Self.loadInstalled().first(where: { $0.key == key }) else { return nil }
        // ls-remote avoids touching the working tree; compares the default-branch HEAD.
        let result = await Self.git(["ls-remote", rec.repoURL, "HEAD"], cwd: nil)
        guard result.exitCode == 0 else { return nil }
        let remoteFull = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " }).first.map(String.init) ?? ""
        guard !remoteFull.isEmpty else { return nil }
        let remoteShort = String(remoteFull.prefix(rec.commitSHA.count))
        guard remoteShort != rec.commitSHA else { return nil }
        return PackUpdateAvailable(key: key, currentSHA: rec.commitSHA, remoteSHA: remoteShort)
    }

    // MARK: - Update: clone the new revision and diff against local

    func cloneUpdate(_ key: String) async throws -> PackUpdate {
        guard let rec = Self.loadInstalled().first(where: { $0.key == key }) else {
            throw PackError.packNotInstalled(key)
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("menumate-pack-update-\(UUID().uuidString)", isDirectory: true)
        let clone = await Self.git(["clone", "--depth", "1", rec.repoURL, tempDir.path], cwd: nil)
        guard clone.exitCode == 0 else {
            try? FileManager.default.removeItem(at: tempDir)
            throw PackError.gitFailed(clone.stderr.isEmpty ? clone.stdout : clone.stderr)
        }

        do {
            let (newManifest, newScripts) = try Self.readManifestAndScripts(in: tempDir)
            let newSHA = await Self.shortHEAD(in: tempDir)
            let diffs = Self.diffScripts(localDir: Self.packDir(key), localManifest: rec.manifest,
                                         newDir: tempDir, newManifest: newManifest)
            return PackUpdate(key: key, tempDir: tempDir, newManifest: newManifest, newSHA: newSHA,
                              newRepoURL: rec.repoURL, newRepo: rec.repo,
                              diffsByFile: diffs, newScripts: newScripts)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }
    }

    // MARK: - Update: apply (preserve enabled state by PackAction.id)

    func applyUpdate(_ key: String, _ update: PackUpdate) throws {
        let fm = FileManager.default
        let dest = Self.packDir(key)

        // Preserve which pack-action-ids were enabled (match by stable PackAction.id,
        // encoded into the deterministic UUID).
        var config = appState().config
        var enabledByPackActionID: [String: Bool] = [:]
        for action in config.actions where action.packID == key {
            if let paID = Self.packActionID(of: action, packKey: key, manifest: update.newManifest) {
                enabledByPackActionID[paID] = action.isEnabled
            }
        }

        // Swap working tree.
        try fm.createDirectory(at: Self.packsRoot, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: update.tempDir, to: dest)

        // Rebuild this pack's actions from the new manifest:
        // - existing PackAction.id keeps its enabled state, new ones default disabled,
        // - removed remote actions drop out.
        config.actions.removeAll { $0.packID == key }
        let baseOrder = (config.actions.map(\.sortOrder).max() ?? -1) + 1
        let newActions = update.newManifest.actions.enumerated().map { offset, pa -> MenuAction in
            var a = Self.menuAction(from: pa, packKey: key, repo: update.newRepo,
                                    packDir: dest, sortOrder: baseOrder + offset)
            a.isEnabled = enabledByPackActionID[pa.id] ?? false
            return a
        }
        config.actions.append(contentsOf: newActions)

        // Update installed.json (new SHA + manifest snapshot).
        var records = Self.loadInstalled().filter { $0.key != key }
        records.append(InstalledRecord(key: key, repoURL: update.newRepoURL, repo: update.newRepo,
                                       commitSHA: update.newSHA, manifest: update.newManifest))
        try Self.saveInstalled(records)

        appState().update(config)
        reload()
    }

    /// Discard a clone/update temp dir without applying (UI cancel path).
    func discard(tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Translation: PackAction → MenuAction

    /// Deterministic UUID for a pack action so enabled-state survives updates and
    /// snapshot rebuilds: derived from packKey + PackAction.id.
    static func actionUUID(packKey: String, packActionID: String) -> UUID {
        UUID.deterministic("pack.\(packKey).\(packActionID)")
    }

    /// Recover a MenuAction's originating PackAction.id by matching its deterministic UUID.
    private static func packActionID(of action: MenuAction, packKey: String,
                                     manifest: PackManifest) -> String? {
        for pa in manifest.actions where actionUUID(packKey: packKey, packActionID: pa.id) == action.id {
            return pa.id
        }
        return nil
    }

    private static func menuAction(from pa: PackAction, packKey: String, repo: String,
                                   packDir: URL, sortOrder: Int) -> MenuAction {
        // Absolute scriptPath into the installed pack dir (validate() already rejected `..`).
        let scriptAbs = packDir.appendingPathComponent(pa.script).path
        let spec = ScriptSpec(scriptPath: scriptAbs, inlineSource: nil, timeoutSeconds: pa.timeoutSeconds)
        return MenuAction(
            id: actionUUID(packKey: packKey, packActionID: pa.id),
            title: pa.title,
            icon: .symbol(pa.icon),
            kind: .runScript(spec),
            matching: MatchRule(targets: pa.targets, utis: pa.utis),
            placement: pa.placement,
            variants: pa.variants,
            presetKey: nil,
            packID: packKey,
            packRepo: repo,
            isEnabled: false,        // ALWAYS disabled on import.
            sortOrder: sortOrder)
    }

    // MARK: - Manifest + script reading

    private static func readManifestAndScripts(in dir: URL) throws -> (PackManifest, [String: String]) {
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL) else {
            throw PackError.noManifest
        }
        let manifest: PackManifest
        do {
            manifest = try PackManifest.decode(data)
            try manifest.validate()
        } catch {
            throw PackError.manifestInvalid("\(error)")
        }
        var scripts: [String: String] = [:]
        for pa in manifest.actions {
            // pa.script already validated as a safe in-repo relative path.
            let url = dir.appendingPathComponent(pa.script)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                scripts[pa.id] = text
            }
        }
        return (manifest, scripts)
    }

    private static func diffScripts(localDir: URL, localManifest: PackManifest,
                                    newDir: URL, newManifest: PackManifest) -> [PackUpdate.FileDiff] {
        // Union of script paths declared by old & new manifests.
        let oldPaths = Set(localManifest.actions.map(\.script))
        let newPaths = Set(newManifest.actions.map(\.script))
        let allPaths = oldPaths.union(newPaths).sorted()
        return allPaths.map { rel in
            let oldText = oldPaths.contains(rel)
                ? try? String(contentsOf: localDir.appendingPathComponent(rel), encoding: .utf8) : nil
            let newText = newPaths.contains(rel)
                ? try? String(contentsOf: newDir.appendingPathComponent(rel), encoding: .utf8) : nil
            return PackUpdate.FileDiff(path: rel, oldText: oldText, newText: newText)
        }
    }

    private static func shortHEAD(in dir: URL) async -> String {
        let r = await git(["rev-parse", "--short", "HEAD"], cwd: dir)
        let sha = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? "unknown" : sha
    }

    // MARK: - git helper (off the main actor; blocking ShellRunner)

    private static func git(_ args: [String], cwd: URL?) async -> ShellResult {
        await Task.detached(priority: .userInitiated) {
            ShellRunner.run("/usr/bin/git", args, cwd: cwd, timeout: 120)
        }.value
    }

    // MARK: - URL / key normalization

    /// `owner/repo` → `https://github.com/owner/repo.git`; https/git URLs pass through.
    static func normalizeRepoURL(_ input: String) -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("git@") || s.hasPrefix("ssh://") {
            return s
        }
        // owner/repo shorthand (exactly one slash, no scheme).
        let parts = s.split(separator: "/")
        if parts.count == 2 {
            let owner = parts[0]
            var repo = parts[1]
            if repo.hasSuffix(".git") { repo = repo.dropLast(4) }
            return "https://github.com/\(owner)/\(repo).git"
        }
        return s
    }

    /// Extract `owner/repo` for display from a full URL or shorthand.
    static func repoDisplay(from urlOrShorthand: String) -> String {
        var s = urlOrShorthand.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        // git@github.com:owner/repo
        if let range = s.range(of: ":"), s.hasPrefix("git@") {
            s = String(s[range.upperBound...])
        } else if let range = s.range(of: "://") {
            // strip scheme + host: keep last two path components.
            let afterScheme = String(s[range.upperBound...])
            let comps = afterScheme.split(separator: "/").map(String.init)
            if comps.count >= 3 { s = comps.suffix(2).joined(separator: "/") }
            else if comps.count == 2 { s = comps.joined(separator: "/") }
        }
        let comps = s.split(separator: "/").map(String.init)
        if comps.count >= 2 { return comps.suffix(2).joined(separator: "/") }
        return s
    }

    /// Filesystem-safe install key derived from owner/repo.
    static func sanitizeKey(_ repo: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = String(repo.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        // collapse runs of "-" and trim, replace path separators (already mapped) ".." safety.
        var key = mapped.replacingOccurrences(of: "/", with: "-")
        while key.contains("--") { key = key.replacingOccurrences(of: "--", with: "-") }
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return key.isEmpty ? "pack-\(abs(repo.hashValue))" : key
    }

    // MARK: - installed.json persistence

    /// Lock file record: enough to rebuild `packs` and run update checks offline.
    struct InstalledRecord: Codable, Equatable {
        let key: String
        let repoURL: String
        let repo: String
        let commitSHA: String
        let manifest: PackManifest
    }

    private static func loadInstalled() -> [InstalledRecord] {
        guard let data = try? Data(contentsOf: installedFile) else { return [] }
        return (try? JSONDecoder().decode([InstalledRecord].self, from: data)) ?? []
    }

    private static func saveInstalled(_ records: [InstalledRecord]) throws {
        try FileManager.default.createDirectory(at: packsRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: installedFile, options: .atomic)
    }
}
