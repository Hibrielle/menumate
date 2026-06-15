import Foundation

public final class ConfigStore {
    public let fileURL: URL
    private var cache: (mtime: Date, config: MenuConfig)?

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("config.json")
    }

    /// 读路径存在两个无害的 TOCTOU 窗口：exists→attributes 间文件被删会抛错（调用方以
    /// try?/seed 兜底）；attributes→read 间被原子替换会以旧 mtime 缓存新内容，下次调用自愈。
    public func load() throws -> MenuConfig {
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

    public func save(_ config: MenuConfig) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}
