import Foundation

/// 仓库里一个文件的审查元信息(导入扩展包时暴露「未在 manifest 声明」的兄弟文件用)。
public struct PackFile: Equatable, Sendable {
    public let relativePath: String
    public let isExecutable: Bool
    public let isBinary: Bool
    public init(relativePath: String, isExecutable: Bool, isBinary: Bool) {
        self.relativePath = relativePath
        self.isExecutable = isExecutable
        self.isBinary = isBinary
    }
}

/// 导入审查的安全网:manifest 只声明少数脚本,但脚本可经相对路径 source 仓库里的其它文件。
/// 若审查只展示声明过的脚本,恶意包就能把真逻辑藏在未声明的兄弟文件里绕过「逐脚本审查」。
/// 这里把【声明之外】值得人看的文件全列出来(含隐藏脚本、可执行、二进制),交给 UI 强制展示。
public enum PackInspector {
    /// 跳过 .git/ 与纯元数据(manifest.json / README* / LICENSE* / *.md / .gitignore / .gitattributes / .DS_Store)。
    /// 故意【不】跳过其它点文件——隐藏脚本(如 `.evil.sh`)恰恰最该被审查者看见。
    public static func undeclaredFiles(inDirectory dir: URL, declared: Set<String>) -> [PackFile] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                     options: [], errorHandler: nil) else { return [] }
        let skipExact: Set<String> = ["manifest.json", ".gitignore", ".gitattributes", ".DS_Store"]
        let base = dir.standardizedFileURL.path
        var out: [PackFile] = []
        for case let url as URL in en {
            if url.pathComponents.contains(".git") { continue }   // 不审查版本库内部
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(base + "/") else { continue }
            let rel = String(full.dropFirst(base.count + 1))
            if declared.contains(rel) { continue }
            let name = url.lastPathComponent
            let lname = name.lowercased()
            if skipExact.contains(name) { continue }
            if lname.hasSuffix(".md") || lname.hasPrefix("readme") || lname.hasPrefix("license") { continue }
            out.append(PackFile(relativePath: rel, isExecutable: isExecutable(url), isBinary: isBinary(url)))
        }
        return out.sorted { $0.relativePath < $1.relativePath }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        guard let perms = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
        else { return false }
        return (perms.intValue & 0o111) != 0
    }

    private static func isBinary(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let chunk = (try? fh.read(upToCount: 4096)) ?? Data()
        if chunk.contains(0) { return true }                  // NUL 字节 → 二进制
        return String(data: chunk, encoding: .utf8) == nil    // 非 UTF-8 → 二进制
    }
}
