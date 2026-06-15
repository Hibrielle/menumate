import Foundation

/// 扩展包清单(`manifest.json`,位于仓库根)。
///
/// 解析策略:
/// - 未知字段一律忽略(向后兼容,允许仓库声明未来字段)。
/// - 缺省值在 decode 阶段填充:pack icon → "shippingbox";action icon → "bolt";
///   author/description nil;utis nil → [];timeoutSeconds nil → 60;placement 缺省 topLevel。
/// - `decode` 只解析不校验;`validate()` 做语义校验(schemaVersion 不超前、name/actions 非空、
///   每个 action 字段合法、脚本路径限定仓库内相对路径)。
public struct PackManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var name: String          // 包名(显示)
    public var author: String?
    public var description: String?
    public var icon: String          // SF Symbol 名,默认 shippingbox
    public var actions: [PackAction]

    public init(schemaVersion: Int, name: String, author: String? = nil,
                description: String? = nil, icon: String = "shippingbox",
                actions: [PackAction]) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.author = author
        self.description = description
        self.icon = icon
        self.actions = actions
    }

    // MARK: Codable (custom: fill defaults, ignore unknown keys)

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, name, author, description, icon, actions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.author = try c.decodeIfPresent(String.self, forKey: .author)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "shippingbox"
        self.actions = try c.decodeIfPresent([PackAction].self, forKey: .actions) ?? []
    }

    // MARK: Decode entry point

    public enum DecodeError: Error, Sendable { case notJSON(String) }

    public static func decode(_ data: Data) throws -> PackManifest {
        do {
            return try JSONDecoder().decode(PackManifest.self, from: data)
        } catch let e as DecodingError {
            throw DecodeError.notJSON("\(e)")
        }
    }

    // MARK: Validation

    public enum ValidationError: Error, Equatable, Sendable {
        case incompatibleSchema(found: Int)
        case emptyName
        case emptyActions
        case duplicateActionID(String)
        case emptyActionID
        case emptyActionTitle(id: String)
        case invalidScriptPath(id: String, path: String)
    }

    public func validate() throws {
        if schemaVersion > Self.currentSchemaVersion {
            throw ValidationError.incompatibleSchema(found: schemaVersion)
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyName
        }
        if actions.isEmpty { throw ValidationError.emptyActions }

        var seen = Set<String>()
        for action in actions {
            let id = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty { throw ValidationError.emptyActionID }
            if !seen.insert(id).inserted { throw ValidationError.duplicateActionID(id) }
            if action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ValidationError.emptyActionTitle(id: id)
            }
            guard Self.isSafeRelativeScriptPath(action.script) else {
                throw ValidationError.invalidScriptPath(id: id, path: action.script)
            }
        }
    }

    /// 仅允许仓库内相对路径:非空、不以 `/` 开头(绝对路径)、任何路径段都不是 `..`。
    /// 单独的 `.` 段无害(stdlib 解析时折叠),但 `..` 一律拒绝以防越界。
    static func isSafeRelativeScriptPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        guard !path.hasPrefix("/") else { return false }
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        for seg in segments where seg == ".." { return false }
        return true
    }
}

/// 包内单个动作声明。`targets`/`placement`/`variants` 复用 Models 里既有的 Codable 类型。
public struct PackAction: Codable, Equatable, Sendable {
    public var id: String            // 包内稳定标识(更新时按它匹配)
    public var title: String
    public var icon: String          // SF Symbol,默认 bolt
    public var script: String        // 相对仓库根的脚本路径,如 "actions/x.zsh"
    public var targets: TargetKind
    public var utis: [String]        // nil → []
    public var placement: Placement  // 缺省 topLevel
    public var variants: VariantSource?
    public var timeoutSeconds: Int   // nil → 60

    public init(id: String, title: String, icon: String = "bolt", script: String,
                targets: TargetKind = .any, utis: [String] = [],
                placement: Placement = .topLevel, variants: VariantSource? = nil,
                timeoutSeconds: Int = 60) {
        self.id = id
        self.title = title
        self.icon = icon
        self.script = script
        self.targets = targets
        self.utis = utis
        self.placement = placement
        self.variants = variants
        self.timeoutSeconds = timeoutSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, icon, script, targets, utis, placement, variants, timeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "bolt"
        self.script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        self.targets = try c.decodeIfPresent(TargetKind.self, forKey: .targets) ?? .any
        self.utis = try c.decodeIfPresent([String].self, forKey: .utis) ?? []
        self.placement = try c.decodeIfPresent(Placement.self, forKey: .placement) ?? .topLevel
        self.variants = try c.decodeIfPresent(ManifestVariant.self, forKey: .variants)?.source
        self.timeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 60
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(icon, forKey: .icon)
        try c.encode(script, forKey: .script)
        try c.encode(targets, forKey: .targets)
        try c.encode(utis, forKey: .utis)
        try c.encode(placement, forKey: .placement)
        try c.encodeIfPresent(variants.map(ManifestVariant.init), forKey: .variants)
        try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
    }
}

/// Human-authored variant shape in `manifest.json`:
///   `"variants": { "fixed": ["png", "jpeg"] }`
///   `"variants": { "directoryListing": "templates" }`
/// This bridges to Models' `VariantSource` (whose synthesized Codable uses an
/// `_0` wrapper that we deliberately do NOT expose in the manifest format).
struct ManifestVariant: Codable, Equatable {
    let source: VariantSource

    init(_ source: VariantSource) { self.source = source }

    private enum CodingKeys: String, CodingKey { case fixed, directoryListing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try c.decodeIfPresent([String].self, forKey: .fixed) {
            source = .fixed(list)
        } else if let dir = try c.decodeIfPresent(String.self, forKey: .directoryListing) {
            source = .directoryListing(dir)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "variants must be {fixed:[...]} or {directoryListing:\"...\"}"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch source {
        case .fixed(let list): try c.encode(list, forKey: .fixed)
        case .directoryListing(let dir): try c.encode(dir, forKey: .directoryListing)
        }
    }
}
