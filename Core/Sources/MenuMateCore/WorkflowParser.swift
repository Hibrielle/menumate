import Foundation

public struct WorkflowService: Equatable {
    public var menuTitle: String
    public var message: String
    public var sendFileTypes: [String]
}

public enum WorkflowParser {
    /// 解析 .workflow/Contents/Info.plist 的 NSServices[0]。
    /// NSServices 是 array of dict，每个元素含：
    ///   "NSMenuItem"    (dict) — "default" 键为人类可读菜单标题
    ///   "NSMessage"     (string, required)
    ///   "NSSendFileTypes" (array of string, optional)
    // v1 仅取 NSServices[0]（Automator 只生成一个）；NSIconName/NSRequiredContext 留待需要时扩展
    public static func parse(infoPlistData: Data) throws -> WorkflowService? {
        guard let root = try PropertyListSerialization.propertyList(from: infoPlistData, format: nil) as? [String: Any],
              let services = root["NSServices"] as? [[String: Any]],
              let first = services.first,
              let message = first["NSMessage"] as? String else { return nil }
        let title = ((first["NSMenuItem"] as? [String: Any])?["default"] as? String) ?? message
        let types = (first["NSSendFileTypes"] as? [String]) ?? []
        return WorkflowService(menuTitle: title, message: message, sendFileTypes: types)
    }
}
