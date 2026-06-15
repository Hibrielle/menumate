import Foundation

/// 对 pbs 的 NSServicesStatus 字典做「键唯一性感知匹配 + 就地改值」的纯函数编辑器。
///
/// 背景（macOS 15 实测）：很多服务共享 (bundleID, NSMessage) —
/// Terminal 两个服务同为 newTerminalAtFolder、Instruments ×4、
/// 所有 Automator 快捷操作共享 (null)+runWorkflowAsService。
/// 纯前后缀模糊匹配会把兄弟服务串改；整键删除会丢用户在系统设置里配的
/// key_equivalent（服务快捷键）与 enabled_services_menu。
///
/// 策略：
/// 1. 精确键优先 — default 标题键 + 本地化标题键；
///    仅当 (bundleID, message) 在枚举服务中唯一时才允许前后缀模糊兜底。
/// 2. 就地改值 — 禁用只翻 enabled_context_menu/presentation_modes.ContextMenu；
///    启用后仅当条目不再携带其他有意义状态时才整键删除；绝不动其他服务的键。
public enum ServiceStatusEditor {

    /// 判断某服务当前是否被禁用（context menu）。命中策略同 apply：精确键优先，唯一时才模糊。
    public static func isDisabled(in status: [String: Any],
                                  bundleID: String?, menuTitle: String, localizedTitle: String?,
                                  message: String, isPairUnique: Bool) -> Bool {
        for key in matchedKeys(in: status, bundleID: bundleID, menuTitle: menuTitle,
                               localizedTitle: localizedTitle, message: message,
                               isPairUnique: isPairUnique) {
            if let entry = status[key] as? [String: Any],
               entry["enabled_context_menu"] as? Bool == false {
                return true
            }
        }
        return false
    }

    /// 计算把某服务设为 enabled/disabled 后的新 NSServicesStatus 字典。
    /// 只改目标服务的条目，其他键原样 pass-through，并保留 key_equivalent/enabled_services_menu。
    public static func apply(enabled: Bool, to status: [String: Any],
                             bundleID: String?, menuTitle: String, localizedTitle: String?,
                             message: String, isPairUnique: Bool) -> [String: Any] {
        var result = status
        let matched = matchedKeys(in: status, bundleID: bundleID, menuTitle: menuTitle,
                                  localizedTitle: localizedTitle, message: message,
                                  isPairUnique: isPairUnique)
        if enabled {
            // 启用：就地翻回 true；不合成新键（无匹配即已是默认启用态）。
            for key in matched {
                guard var entry = status[key] as? [String: Any] else {
                    // 值形状异常（非字典）——该键确属本服务，直接清掉
                    result.removeValue(forKey: key)
                    continue
                }
                entry["enabled_context_menu"] = true
                var pm = (entry["presentation_modes"] as? [String: Any]) ?? [:]
                pm["ContextMenu"] = true
                entry["presentation_modes"] = pm
                if isRemovableAfterEnable(entry) {
                    result.removeValue(forKey: key)
                } else {
                    result[key] = entry
                }
            }
        } else {
            // 禁用：优先就地改已命中的键；无命中则合成 default 标题键，
            // pair 非唯一（无模糊兜底）且有不同本地化标题时双写以最大化系统命中。
            var targets = matched
            if targets.isEmpty {
                targets = [PbsKey.statusKey(bundleID: bundleID, menuTitle: menuTitle, message: message)]
                if !isPairUnique, let loc = localizedTitle, loc != menuTitle {
                    targets.append(PbsKey.statusKey(bundleID: bundleID, menuTitle: loc, message: message))
                }
            }
            for key in targets {
                var entry = (status[key] as? [String: Any]) ?? [:]
                entry["enabled_context_menu"] = false
                var pm = (entry["presentation_modes"] as? [String: Any]) ?? [:]
                pm["ContextMenu"] = false
                if pm["ServicesMenu"] == nil { pm["ServicesMenu"] = false }   // 已有值原样保留
                entry["presentation_modes"] = pm
                // key_equivalent / enabled_services_menu 一概不动
                result[key] = entry
            }
        }
        return result
    }

    // MARK: - 匹配

    /// 命中的 status 键：精确键（default + 本地化标题）存在则用之；
    /// 否则仅当 (bundleID, message) 唯一时回退前后缀模糊匹配；再无则空。
    static func matchedKeys(in status: [String: Any],
                            bundleID: String?, menuTitle: String, localizedTitle: String?,
                            message: String, isPairUnique: Bool) -> [String] {
        var exact = [PbsKey.statusKey(bundleID: bundleID, menuTitle: menuTitle, message: message)]
        if let loc = localizedTitle, loc != menuTitle {
            exact.append(PbsKey.statusKey(bundleID: bundleID, menuTitle: loc, message: message))
        }
        let present = exact.filter { status[$0] != nil }
        if !present.isEmpty { return present }
        guard isPairUnique else { return [] }
        let prefix = "\(bundleID ?? "(null)") - "
        let suffix = " - \(message)"
        return status.keys
            // 长度护栏：防止 "(null) - runWorkflowAsService" 这类前后缀重叠的退化键误命中
            .filter { $0.count >= prefix.count + suffix.count
                && $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
            .sorted()
    }

    /// enable 后是否可整键删除：仅当条目等价于「我们自己合成的全 false 禁用形状」被启用后的样子 —
    /// 没有 key_equivalent 等额外键，且 enabled_services_menu 不为 false
    /// （false 是服务菜单维度需保留的用户/历史状态）。
    private static func isRemovableAfterEnable(_ entry: [String: Any]) -> Bool {
        let managed: Set<String> = ["enabled_context_menu", "enabled_services_menu", "presentation_modes"]
        guard entry.keys.allSatisfy({ managed.contains($0) }) else { return false }
        if entry["enabled_services_menu"] as? Bool == false { return false }
        if let pm = entry["presentation_modes"] as? [String: Any] {
            let known: Set<String> = ["ContextMenu", "ServicesMenu"]
            guard pm.keys.allSatisfy({ known.contains($0) }) else { return false }
        }
        return true
    }
}
