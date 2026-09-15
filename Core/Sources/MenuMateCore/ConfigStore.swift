import Foundation

public final class ConfigStore {
    public let fileURL: URL
    private var cache: (mtime: Date, config: MenuConfig)?

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    /// 读路径存在两个无害的 TOCTOU 窗口：exists→attributes 间文件被删会抛错（调用方以
    /// try?/seed 兜底）；attributes→read 间被原子替换会以旧 mtime 缓存新内容，下次调用自愈。
    public func load(fresh: Bool = false) throws -> MenuConfig {
        if fresh { cache = nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return .defaultSeed() }
        let mtime = (try fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? .distantPast
        if let cache, cache.mtime == mtime { return cache.config }
        let data = try Data(contentsOf: fileURL)
        // 两阶段读取：先探版本（未来版本给出可诊断错误），再完整解码
        let version = try MenuConfig.schemaVersion(of: data)
        guard version <= MenuConfig.currentSchemaVersion else {
            throw MenuConfig.IncompatibleSchema(found: version)
        }
        let config = try JSONDecoder().decode(MenuConfig.self, from: data)
        cache = (mtime, config)
        return config
    }

    public func save(_ config: MenuConfig, expected: MenuConfig? = nil) throws {
        try StorageLock.perform(in: fileURL.deletingLastPathComponent()) {
            guard !PackTransaction(directory: fileURL.deletingLastPathComponent()).needsRecovery else {
                throw PackTransaction.Failure.pendingRecovery
            }
            if let expected {
                let current: MenuConfig
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    current = try JSONDecoder().decode(MenuConfig.self, from: Data(contentsOf: fileURL))
                } else { current = .defaultSeed() }
                guard current == expected else { throw PackTransaction.Failure.configurationChanged }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
            cache = nil
        }
    }
}
