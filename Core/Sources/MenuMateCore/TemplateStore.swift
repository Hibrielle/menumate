import Foundation

public enum TemplateStore {
    /// 列举目录中的常规文件名（排序后截断到 maxEntries，防超长菜单）。
    /// 子目录、隐藏文件被过滤——子目录名混入会变成点击后必失败的菜单项。
    public static func list(in directory: URL, maxEntries: Int = 50) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles)) ?? []
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .map { $0.lastPathComponent }
            .sorted()
            .prefix(maxEntries)
            .map { $0 }
    }
}
