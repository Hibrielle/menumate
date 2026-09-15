import Foundation

/// Optional local HTML entry. Script-only actions remain unchanged.
public struct ActionInterface: Codable, Equatable, Sendable {
    /// WebKit content filters do not support regex alternation (`|`). Keep
    /// protocols in separate rules so reviewed local pages cannot load remote code.
    public static let localContentRules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]"#

    public var entry: String
    public var width: Int
    public var height: Int
    public init(entry: String, width: Int = 500, height: Int = 600) {
        self.entry = entry; self.width = width; self.height = height
    }
    private enum CodingKeys: String, CodingKey { case entry, width, height }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decode(String.self, forKey: .entry)
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 500
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 600
    }
    public func resolvedURL(base: URL) -> URL {
        entry.hasPrefix("/") ? URL(fileURLWithPath: entry) : base.appendingPathComponent(entry)
    }
}

public enum ActionParameters {
    public static let maximumBytes = 65_536
    public enum Invalid: Error { case notAnObject, tooLarge }
    public static func encode(_ object: Any) throws -> String {
        guard object is [String: Any], JSONSerialization.isValidJSONObject(object) else { throw Invalid.notAnObject }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= maximumBytes else { throw Invalid.tooLarge }
        return String(decoding: data, as: UTF8.self)
    }
    public static func decode(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        guard data.count <= maximumBytes else { throw Invalid.tooLarge }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Invalid.notAnObject }
        return object
    }
}
