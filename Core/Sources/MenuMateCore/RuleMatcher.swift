import Foundation
import UniformTypeIdentifiers

public enum MatchContext {
    case items([URL])
    case container(URL)
}

public enum RuleMatcher {
    public static func visibleActions(in config: MenuConfig, context: MatchContext) -> [MenuAction] {
        config.actions
            .filter { $0.isEnabled && matches(rule: $0.matching, context: context) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public static func matches(rule: MatchRule, context: MatchContext) -> Bool {
        switch context {
        case .container:
            return rule.targets == .container
        case .items(let urls):
            guard rule.targets != .container, !urls.isEmpty else { return false }
            if let max = rule.maxSelectionCount, urls.count > max { return false }
            if let min = rule.minSelectionCount, urls.count < min { return false }
            return urls.allSatisfy { matches(rule: rule, url: $0) }
        }
    }

    private static func matches(rule: MatchRule, url: URL) -> Bool {
        var isDirObjC: ObjCBool = false
        // fileExists 在 FinderSync 沙盒内可用：扩展监控 "/"，系统授予被监控路径的 stat 权限。
        // 若失败（实践中不可达）isDir 退化为 false → .folders 规则隐藏该项，安全降级。
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirObjC)
        let isDir = isDirObjC.boolValue
        switch rule.targets {
        case .files: if isDir { return false }
        case .folders: if !isDir { return false }
        case .any, .container: break  // .container 在上层 guard 已拦截，此处仅为穷举
        }
        guard !rule.utis.isEmpty else { return true }
        let type: UTType? = isDir ? .folder : UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return rule.utis.contains { uti in UTType(uti).map(type.conforms(to:)) ?? false }
    }
}
