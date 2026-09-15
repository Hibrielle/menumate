@_exported import Combine
import Foundation
import MenuMateCore

// Only platform services are replaced. Production AppState, ConfigStore, PackManager
// and transaction code perform real I/O under an isolated root.
enum AppPaths {
    static var root = ProcessInfo.processInfo.environment["MENUMATE_TEST_ROOT"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    static func configDirectory() -> URL { root.appendingPathComponent("config") }
    static func scriptsDirectory() -> URL { configDirectory().appendingPathComponent("Scripts") }
    static func templatesDirectory() -> URL { configDirectory().appendingPathComponent("Templates") }
    static func dataDirectory() -> URL { configDirectory().appendingPathComponent("Data") }
}
enum SettingsTab { case contextMenu, packs, general }
enum PresetSeeder {
    static func seedIfNeeded() {}
    static func mergeNewPresets(into config: MenuConfig) -> MenuConfig? { nil }
    static func recordSeededPresets(in config: MenuConfig) {}
}
enum IconStore {
    static var pruneCount = 0
    static func pruneOrphans(keeping: Set<String>) { pruneCount += 1 }
    static func base64PNG(for file: String) -> String? { nil }
}
final class ActionListener { func start() {} }
// Tests must never broadcast fixture actions to the user's Finder extension.
final class DistributedNotificationCenter {
    static let shared = DistributedNotificationCenter()
    static func `default`() -> DistributedNotificationCenter { shared }
    var posts = 0
    func addObserver(forName: Notification.Name?, object: Any?, queue: OperationQueue?, using: @escaping (Notification) -> Void) {}
    func postNotificationName(_ name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?, deliverImmediately: Bool) { posts += 1 }
}
