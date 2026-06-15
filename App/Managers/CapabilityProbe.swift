import Foundation
import MenuMateCore

struct Capabilities: Codable {
    var osVersion: String
    var pbsReadable: Bool
    var pluginkitAvailable: Bool
    var lsregisterUnregister: Bool
}

/// pbs/pluginkit/lsregister 均为私有机制。每个 OS 版本首跑探测一次并缓存；
/// 探测失败的功能进入「只读 + 跳系统设置」降级模式。
enum CapabilityProbe {
    // Mirror of OpenWithCleaner.lsregisterPath.
    // OpenWithCleaner.lsregisterPath is a static let on a @MainActor class; accessing it
    // from non-isolated context causes a Swift strict-concurrency error at compile time.
    // Inlining the identical constant here is the minimum-impact fix.
    private static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    static func current() -> Capabilities {
        let key = cacheKey()
        if let data = UserDefaults.standard.data(forKey: key),
           let cached = try? JSONDecoder().decode(Capabilities.self, from: data) {
            return cached
        }
        let caps = probeAll()
        cacheIfAllSucceeded(caps, key: key)
        return caps
    }

    /// 只读缓存，不触发任何探测（用于 UI 同步初始化，避免主线程阻塞）
    static func cachedOrUnknown() -> Capabilities {
        if let data = UserDefaults.standard.data(forKey: cacheKey()),
           let cached = try? JSONDecoder().decode(Capabilities.self, from: data) {
            return cached
        }
        // 未探测过：乐观假设可用，onAppear 的异步探测会纠正
        return Capabilities(osVersion: osVersionString(), pbsReadable: true,
                            pluginkitAvailable: true, lsregisterUnregister: true)
    }

    /// 忽略并覆盖缓存，强制重新探测（Onboarding 自检 / 刷新按钮用）。
    static func reprobe() -> Capabilities {
        let key = cacheKey()
        UserDefaults.standard.removeObject(forKey: key)
        let caps = probeAll()
        cacheIfAllSucceeded(caps, key: key)
        return caps
    }

    private static func probeAll() -> Capabilities {
        Capabilities(osVersion: osVersionString(),
                     pbsReadable: probePbs(),
                     pluginkitAvailable: probePluginkit(),
                     lsregisterUnregister: probeLsregister())
    }

    /// 只在三项探测全部成功时落盘；任一失败可能是瞬时的（如 pluginkit 高负载超时），
    /// 不缓存失败结果，下次启动重新探测，避免永久降级。
    private static func cacheIfAllSucceeded(_ caps: Capabilities, key: String) {
        guard caps.pbsReadable, caps.pluginkitAvailable, caps.lsregisterUnregister else { return }
        if let data = try? JSONEncoder().encode(caps) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func cacheKey() -> String { "capabilities-\(osVersionString())" }

    static func probePbs() -> Bool {
        guard let defaults = UserDefaults(suiteName: "pbs") else { return false }
        let value = defaults.object(forKey: "NSServicesStatus")
        return value == nil || value is [String: Any]   // 不存在（从未禁用过）或类型符合预期
    }

    static func probePluginkit() -> Bool {
        guard FileManager.default.fileExists(atPath: "/usr/bin/pluginkit") else { return false }
        let r = ShellRunner.run("/usr/bin/pluginkit", ["-m", "-p", "com.apple.FinderSync"], timeout: 10)
        return r.exitCode == 0
    }

    static func probeLsregister() -> Bool {
        guard FileManager.default.fileExists(atPath: lsregisterPath) else { return false }
        let r = ShellRunner.run(lsregisterPath, ["-h"], timeout: 10)
        return (r.stdout + r.stderr).contains("-u")
    }

    static func osVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }
}
