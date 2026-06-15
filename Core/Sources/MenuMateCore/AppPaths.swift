import Foundation

/// 所有数据放用户 Application Support（非受保护目录）：主 App 与 zsh 子进程自由读写。
/// macOS 14/15 的「访问其他 App 数据」保护只覆盖 ~/Library/Containers 与 Group Containers，
/// 这里刻意完全避开——这是消除授权弹窗的架构前提，勿改回共享容器。
public enum AppPaths {
    /// 配置根目录；ScriptSpec/VariantSource 的相对路径均基于此目录解析
    public static func configDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenuMate", isDirectory: true)
    }

    public static func scriptsDirectory() -> URL {
        configDirectory().appendingPathComponent("Scripts", isDirectory: true)
    }

    public static func templatesDirectory() -> URL {
        configDirectory().appendingPathComponent("Templates", isDirectory: true)
    }

    /// 用户导入的自定义动作图标存放目录（主 App 读写，非受保护区）。
    /// 扩展零文件访问，故图标字节随快照 base64 带过去，不从此目录读。
    public static func iconsDirectory() -> URL {
        configDirectory().appendingPathComponent("Icons", isDirectory: true)
    }

    /// 脚本可自由持久化状态的目录（经 MENUMATE_DATA 暴露，如 cut.sh 的 cutbuffer）
    public static func dataDirectory() -> URL {
        configDirectory().appendingPathComponent("Data", isDirectory: true)
    }
}
