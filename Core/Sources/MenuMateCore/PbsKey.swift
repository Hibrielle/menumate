import Foundation

public enum PbsKey {
    /// NSServicesStatus 字典的 key："<bundle-id> - <菜单名> - <NSMessage>"
    /// 无 bundle id 的 .workflow 服务，第一段为字面量 "(null)"。
    public static func statusKey(bundleID: String?, menuTitle: String, message: String) -> String {
        "\(bundleID ?? "(null)") - \(menuTitle) - \(message)"
    }

    /// 禁用某服务时写入 NSServicesStatus 的值结构。
    public static func disabledStatusValue() -> [String: Any] {
        ["enabled_context_menu": false,
         "enabled_services_menu": false,
         "presentation_modes": ["ContextMenu": false, "ServicesMenu": false]]
    }
}
