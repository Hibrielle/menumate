import Foundation

public enum IPC {
    public static let actionNotification = "com.menumate.action"
    public static let heartbeatNotification = "com.menumate.heartbeat"
    /// 主 App → 扩展：推送 ExtensionSnapshot 的分块（ChunkedTransport.Chunk JSON）
    public static let snapshotNotification = "com.menumate.snapshot"
    /// 扩展 → 主 App：请求立即推送一份快照（扩展启动或尚无快照时）
    public static let snapshotRequestNotification = "com.menumate.snapshot-request"
    /// 单次动作的选中路径数上限；扩展画菜单与主 App 派发闸门共用此常量。
    public static let maxPaths = 1000
}

public struct ActionRequest: Codable, Equatable {
    public var actionID: UUID
    public var variant: String?
    public var paths: [String]

    public init(actionID: UUID, variant: String? = nil, paths: [String]) {
        self.actionID = actionID; self.variant = variant; self.paths = paths
    }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes   // 路径密集，控制分块信封的二次转义膨胀
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(_ string: String) throws -> ActionRequest {
        try JSONDecoder().decode(ActionRequest.self, from: Data(string.utf8))
    }
}

/// 主 App 推送给扩展的完整菜单快照：配置 + 预解析的目录列举（扩展零文件访问）。
public struct ExtensionSnapshot: Codable, Equatable {
    public var config: MenuConfig
    public var variantListings: [UUID: [String]]
    /// 自定义图片图标字节：key = action.id.uuidString，value = 该动作图标的 base64(PNG)。
    /// 仅对 `.imageFile` 动作填充；扩展零文件访问，靠这份字节直接画菜单图标。
    public var iconImages: [String: String]

    public init(config: MenuConfig, variantListings: [UUID: [String]],
                iconImages: [String: String] = [:]) {
        self.config = config; self.variantListings = variantListings
        self.iconImages = iconImages
    }

    enum CodingKeys: String, CodingKey {
        case config, variantListings, iconImages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        config = try c.decode(MenuConfig.self, forKey: .config)
        variantListings = try c.decode([UUID: [String]].self, forKey: .variantListings)
        // 向后兼容：旧快照无 iconImages 字段，解码落空字典
        iconImages = try c.decodeIfPresent([String: String].self, forKey: .iconImages) ?? [:]
    }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    public static func decode(_ s: String) throws -> ExtensionSnapshot {
        try JSONDecoder().decode(ExtensionSnapshot.self, from: Data(s.utf8))
    }
}
