import Foundation

public struct FinderExtensionInfo: Equatable {
    public enum Election: Equatable { case use, ignore, unknown }
    public var election: Election
    public var bundleID: String
    public var version: String
    public var path: String
}

/// 解析 `pluginkit -m -p com.apple.FinderSync -v` 输出。
///
/// 行格式（按 macOS 15.x 真实 -v 输出，无公开文档）：
///   `<+|-|!|空>  <bundle-id>(<version>)\t<uuid>\t<date> <time> +0000\t<path>`
///
/// 注：macOS 15 的 -v 输出在 UUID 后额外插入了一个日期时间字段（格式 YYYY-MM-DD HH:MM:SS +0000）。
/// 解析器同时兼容旧格式（无日期字段，UUID 后直接接路径）。
/// 尾部 "(N plug-ins)" 汇总行会被自动忽略（无括号版本号 / 不含绝对路径）。
public enum PluginkitParser {
    public static func parse(_ output: String) -> [FinderExtensionInfo] {
        output.split(separator: "\n").compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> FinderExtensionInfo? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 选举标记在原始行行首（先于 trimmingCharacters 读取）
        let election: FinderExtensionInfo.Election
        switch line.first {
        case "+": election = .use
        case "-": election = .ignore
        default:  election = .unknown
        }

        // 去掉选举标记字符（+/-/!/?）
        if let first = trimmed.first, "+-!?".contains(first) {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // 提取 bundleID 和 version：<bundle-id>(<version>)
        // 先拆出第一个 tab 字段（含 bundle-id 和 version），再用 firstIndex("(") + lastIndex(")")
        // 定位版本段——即使版本号自身含括号（如 "1.2 (345)"）也能正确切分，bundle id 不被误截。
        let firstField: String
        let restAfterFirstField: String
        if let tabIdx = trimmed.firstIndex(of: "\t") {
            firstField = String(trimmed[..<tabIdx])
            restAfterFirstField = String(trimmed[trimmed.index(after: tabIdx)...])
        } else {
            firstField = trimmed
            restAfterFirstField = ""
        }

        guard let parenOpen  = firstField.firstIndex(of: "("),
              let parenClose = firstField.lastIndex(of: ")") else { return nil }
        // parenOpen must come before parenClose
        guard parenOpen < parenClose else { return nil }

        let bundleID = String(firstField[..<parenOpen])
        let version  = String(firstField[firstField.index(after: parenOpen)..<parenClose])

        // 汇总行（如 " (5 plug-ins)"）因无以 / 开头的路径字段而被丢弃
        guard !bundleID.contains(" ") else { return nil }

        // 从第一 tab 字段之后找第一个以 "/" 开头的 tab-separated 字段
        // 格式：<uuid>\t[date time +0000\t]<path>
        let fields = restAfterFirstField.components(separatedBy: "\t").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        // 找第一个以 "/" 开头的字段作为路径（兼容有无日期字段两种格式）
        guard let path = fields.first(where: { $0.hasPrefix("/") }) else { return nil }
        guard !bundleID.isEmpty else { return nil }

        return FinderExtensionInfo(election: election, bundleID: bundleID, version: version, path: path)
    }
}
