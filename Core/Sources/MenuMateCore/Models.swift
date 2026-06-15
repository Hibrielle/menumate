import Foundation
import CryptoKit

public enum IconSpec: Codable, Equatable, Sendable {
    case symbol(String)
    case imageFile(String)   // 相对数据目录 Icons/ 的文件名（AppPaths.iconsDirectory）

    /// `.imageFile` 时返回文件名，否则 nil。
    public var imageFileName: String? {
        if case .imageFile(let name) = self { return name }
        return nil
    }

    /// SF Symbol 名；`.imageFile` 时返回兜底符号 "photo"（图片缺失时的占位）。
    public var symbolName: String {
        switch self {
        case .symbol(let s): return s
        case .imageFile: return "photo"
        }
    }
}

public enum Placement: String, Codable, Sendable { case topLevel, submenu }

public enum TargetKind: String, Codable, Sendable { case files, folders, any, container }

/// 通用子菜单展开机制：任何动作都可声明 variants，
/// 子项的值在执行时经 MENUMATE_VARIANT 环境变量传给脚本。
public enum VariantSource: Codable, Equatable, Sendable {
    case fixed([String])
    case directoryListing(String)   // 相对路径基于配置目录（AppPaths.configDirectory）解析；绝对路径原样使用
}

public struct MatchRule: Codable, Equatable, Sendable {
    public var targets: TargetKind
    public var utis: [String]
    public var maxSelectionCount: Int?
    public init(targets: TargetKind = .any, utis: [String] = [], maxSelectionCount: Int? = nil) {
        self.targets = targets; self.utis = utis; self.maxSelectionCount = maxSelectionCount
    }
}

// MARK: - Deterministic UUID

public extension UUID {
    /// 由稳定字符串派生确定性 UUID（v5 风格：SHA-256 截断 + 版本/变体位）
    static func deterministic(_ name: String) -> UUID {
        let digest = SHA256.hash(data: Data("com.menumate.preset.\(name)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - ScriptSpec

/// scriptPath 与 inlineSource 同时存在时以 scriptPath 为准（执行层约定）；两者皆空的动作执行为 no-op。
public struct ScriptSpec: Codable, Equatable, Sendable {
    public var scriptPath: String?     // 相对路径基于配置目录；绝对路径原样
    public var inlineSource: String?
    public var timeoutSeconds: Int
    public init(scriptPath: String? = nil, inlineSource: String? = nil, timeoutSeconds: Int = 60) {
        self.scriptPath = scriptPath; self.inlineSource = inlineSource; self.timeoutSeconds = timeoutSeconds
    }

    public func resolvedScriptPath(base: URL) -> String? {
        guard let scriptPath else { return nil }
        return scriptPath.hasPrefix("/") ? scriptPath : base.appendingPathComponent(scriptPath).path
    }
}

public struct MenuAction: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case runScript(ScriptSpec)
        case openWith(appBundleID: String)
    }
    public var id: UUID
    public var title: String
    public var icon: IconSpec
    public var kind: Kind
    public var matching: MatchRule
    public var placement: Placement
    public var variants: VariantSource?
    public var presetKey: String?     // 出厂预设标识；用户自建为 nil
    public var packID: String?        // nil=自有/预设；非 nil=来自该扩展包，脚本只读
    public var packRepo: String?      // owner/repo，用于「打开仓库主页」
    public var iconHue: String?       // 用户自定义图标配色(AppIconHue 原值);nil=按来源/类型派生。仅影响 App 内预览,Finder 菜单图标为单色 SF Symbol
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(id: UUID, title: String, icon: IconSpec, kind: Kind, matching: MatchRule,
                placement: Placement, variants: VariantSource? = nil, presetKey: String? = nil,
                packID: String? = nil, packRepo: String? = nil, iconHue: String? = nil,
                isEnabled: Bool, sortOrder: Int) {
        self.id = id; self.title = title; self.icon = icon; self.kind = kind
        self.matching = matching; self.placement = placement
        self.variants = variants; self.presetKey = presetKey
        self.packID = packID; self.packRepo = packRepo; self.iconHue = iconHue
        self.isEnabled = isEnabled; self.sortOrder = sortOrder
    }
}

public struct MenuConfig: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var actions: [MenuAction]
    public init(schemaVersion: Int, actions: [MenuAction]) {
        self.schemaVersion = schemaVersion; self.actions = actions
    }

    public struct IncompatibleSchema: Error, Sendable {
        public let found: Int
    }
    public func validate() throws {
        if schemaVersion > Self.currentSchemaVersion { throw IncompatibleSchema(found: schemaVersion) }
    }

    /// 两阶段读取的探针：只解 schemaVersion，避免未来版本在完整 decode 阶段抛出无诊断信息的 DecodingError
    public static func schemaVersion(of data: Data) throws -> Int {
        struct Probe: Decodable { let schemaVersion: Int }
        return try JSONDecoder().decode(Probe.self, from: data).schemaVersion
    }
}

public extension MenuConfig {
    /// 出厂预设：全部为脚本动作，脚本本体见 App/PresetScripts/，首启落盘到 Application Support 的 Scripts/
    static func defaultSeed() -> MenuConfig {
        // titleKey 为英文基准键;随安装语言查 Core 自带的 Localizable.xcstrings(中文等)落盘。
        func preset(_ key: String, _ titleKey: String.LocalizationValue, _ symbol: String, _ script: String,
                    _ rule: MatchRule, _ order: Int, variants: VariantSource? = nil) -> MenuAction {
            MenuAction(id: UUID.deterministic(key),
                       title: String(localized: titleKey, bundle: .module), icon: .symbol(symbol),
                       kind: .runScript(ScriptSpec(scriptPath: "Scripts/\(script)")),
                       matching: rule, placement: .topLevel, variants: variants,
                       presetKey: key, isEnabled: true, sortOrder: order)
        }
        return MenuConfig(schemaVersion: currentSchemaVersion, actions: [
            preset("copy-path", "preset.copyPath", "doc.on.doc", "copy-path.sh",
                   MatchRule(targets: .any), 0),
            preset("new-file", "preset.newFile", "doc.badge.plus", "new-file.sh",
                   MatchRule(targets: .container), 1, variants: .directoryListing("Templates")),
            preset("open-terminal", "preset.openTerminal", "terminal", "open-terminal.sh",
                   MatchRule(targets: .any), 2),
            preset("open-editor", "preset.openEditor", "chevron.left.slash.chevron.right", "open-editor.sh",
                   MatchRule(targets: .any), 3),
            preset("image-convert", "preset.convertImage", "photo.on.rectangle", "image-convert.sh",
                   MatchRule(targets: .files, utis: ["public.image"]), 4,
                   variants: .fixed(["png", "jpeg", "heic", "tiff"])),
            preset("cut", "preset.cut", "scissors", "cut.sh", MatchRule(targets: .any), 5),
            preset("paste", "preset.pasteHere", "doc.on.clipboard", "paste.sh",
                   MatchRule(targets: .container), 6),
            preset("open-parent", "preset.goUp", "arrow.up", "open-parent.sh",
                   MatchRule(targets: .container), 7),
            // 与上面同名:右键空白处(open-parent/.container)与右键文件(此条/.any)互斥,
            // 用户无论点哪里都看到一个「上一层」,行为一致。
            preset("open-enclosing", "preset.goUp", "arrow.up", "open-enclosing.sh",
                   MatchRule(targets: .any), 8),
        ])
    }
}
