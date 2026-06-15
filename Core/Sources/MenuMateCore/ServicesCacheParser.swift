import Foundation

public struct ServiceItem: Equatable, Identifiable {
    /// pbs 键的标题段使用 default 还是本地化标题在 macOS 15 上无法静态验证；
    /// 读写 NSServicesStatus 须经 ServiceStatusEditor：精确键（default/localized）优先，
    /// 仅当 (bundleID, message) 在枚举服务中唯一时才允许前后缀模糊匹配。
    public var id: String { PbsKey.statusKey(bundleID: bundleID, menuTitle: menuTitle, message: message) }
    public var bundleID: String?
    public var menuTitle: String
    /// 缓存中解析到的本地化标题，可能与 default 相同或缺失。
    public var localizedTitle: String?
    public var message: String
    public var bundlePath: String?
    /// NSMenuItem 缺失/空 = 非菜单服务（如 AppleSpell）——UI 不应展示，写 pbs 键更是垃圾写入。
    public var hasMenuItem: Bool

    public init(bundleID: String?, menuTitle: String, localizedTitle: String? = nil,
                message: String, bundlePath: String?, hasMenuItem: Bool = true) {
        self.bundleID = bundleID; self.menuTitle = menuTitle
        self.localizedTitle = localizedTitle
        self.message = message; self.bundlePath = bundlePath
        self.hasMenuItem = hasMenuItem
    }
}

/// 解析 ~/Library/Preferences/com.apple.ServicesMenu.Services.plist（pbs 的服务缓存）。
///
/// 真实结构（macOS 15.x 验证）：
///   root (dict)
///     "NSServices" (dict)
///       "CFPrincipalLocalizations" (array) — 忽略
///       "CFVendedServices" (array of dict)
///         each entry:
///           "NSBundleIdentifier" (string, optional)
///           "NSBundlePath"       (string, optional)
///           "NSMessage"          (string, required)
///           "NSMenuItem"         (dict, optional)
///             "default"          (string) — 英文/原始菜单标题
///             "empty"            (string) — 本地化菜单标题（macOS 15 实测键名）
///             其他 locale 键（如 "zh-Hans", "zh_CN", "English" 等）
///
/// 注意："NSServices" 是一个中间字典，CFVendedServices 不在根层级。
/// 部分服务的 NSMenuItem 为空字典（如 AppleSpell），此时 hasMenuItem=false，menuTitle 退回 NSMessage。
public enum ServicesCacheParser {
    public static func parse(plistData: Data) throws -> [ServiceItem] {
        guard let root = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return []
        }
        // macOS 15 实际结构：root["NSServices"]["CFVendedServices"]
        let nsServices = root["NSServices"] as? [String: Any]
        let vended = (nsServices?["CFVendedServices"] as? [[String: Any]])
            // 兼容假设性旧格式（CFVendedServices 直接在 root）
            ?? (root["CFVendedServices"] as? [[String: Any]])
            ?? []
        return vended.compactMap { dict in
            guard let message = dict["NSMessage"] as? String else { return nil }
            let menuItem = dict["NSMenuItem"] as? [String: Any]
            // NSMenuItem 存在且非空字典且有 default 键才算真正的菜单服务
            let hasMenuItem = menuItem != nil && !(menuItem!.isEmpty) && menuItem!["default"] != nil
            let title = (menuItem?["default"] as? String) ?? message
            // 本地化标题存储在 "empty" 键（macOS 15 实测，CFPrincipalLocalizations=["zh-Hans"] 场景）
            let localizedTitle = menuItem?["empty"] as? String
            return ServiceItem(bundleID: dict["NSBundleIdentifier"] as? String,
                               menuTitle: title,
                               localizedTitle: localizedTitle,
                               message: message,
                               bundlePath: dict["NSBundlePath"] as? String,
                               hasMenuItem: hasMenuItem)
        }
    }
}
