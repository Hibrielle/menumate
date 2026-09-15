import Foundation

/// Keep scripts and HTML resources stable while an action is queued, running or has an open dialog.
@MainActor enum PackUsage {
    private static var counts: [String: Int] = [:]
    static func retain(_ key: String?) { if let key { counts[key, default: 0] += 1 } }
    static func release(_ key: String?) {
        guard let key else { return }
        let remaining = (counts[key] ?? 1) - 1
        if remaining > 0 { counts[key] = remaining } else { counts.removeValue(forKey: key) }
    }
    static func isBusy(_ key: String) -> Bool { counts[key, default: 0] > 0 }
}
