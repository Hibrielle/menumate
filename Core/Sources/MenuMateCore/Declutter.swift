import Foundation

/// 「一键整理」的纯判定:某个注入项是否来自第三方(可作为"推荐隐藏"的预勾依据)。
/// 第三方 = 不是 Apple(`com.apple.*` 或 `/System` 路径)、不是 MenuMate(`com.menumate.*`),
/// 且有可识别来源;无任何标识(bundleID 与 path 都缺)→ 视为未知,不预勾(保守,不误伤)。
public enum Declutter {
    public static func isThirdParty(bundleID: String?, bundlePath: String?) -> Bool {
        if let b = bundleID {
            if b.hasPrefix("com.apple.") || b.hasPrefix("com.menumate.") { return false }
            return true
        }
        if let p = bundlePath { return !p.hasPrefix("/System/") }
        return false
    }
}
