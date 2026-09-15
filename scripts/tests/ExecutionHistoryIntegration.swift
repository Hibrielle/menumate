@_exported import Combine
import Foundation
import MenuMateCore

// Compile the actual runner and history manager, replacing only app preferences,
// notification delivery, and filesystem roots with isolated test support.
enum AppPaths {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    static func configDirectory() -> URL { root }
    static func templatesDirectory() -> URL { root.appendingPathComponent("Templates") }
    static func dataDirectory() -> URL { root.appendingPathComponent("Data") }
}
enum AppPrefs {
    static let terminalBundleID: String? = nil
    static let editorBundleID: String? = nil
}
protocol ActionRunning {
    @MainActor func run(action: MenuAction, variant: String?, urls: [URL])
}
@MainActor enum Notifier {
    static var failures = 0
    static func showFailure(_ title: String, _ message: String) { failures += 1 }
}
@MainActor final class AppState {
    static let shared = AppState()
    var storageRecoveryRequired = false
}
@main struct ExecutionHistoryIntegration {
    @MainActor static func main() async throws {
        let fm = FileManager.default, root = AppPaths.root
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let log = ExecutionLog.shared // Its AppPaths root is isolated above.
        var action = MenuAction(id: UUID(), title: "History test", icon: .symbol("bolt"),
            kind: .runScript(ScriptSpec(inlineSource: "printf 'summary\\nsecond line\\n'; printf 'diagnostic\\n' >&2")),
            matching: MatchRule(), placement: .topLevel, isEnabled: true, sortOrder: 0)
        func run(_ action: MenuAction, record: Bool = true) async -> ShellResult {
            await withCheckedContinuation { continuation in
                ActionRunner().runWithResult(action: action, variant: "test-option", urls: [root], recordExecution: record) {
                    continuation.resume(returning: $0)
                }
            }
        }
        let result = await run(action)
        precondition(result.exitCode == 0 && log.records.count == 1)
        precondition(log.records[0].stdout == "summary\nsecond line\n")
        precondition(log.records[0].stderr == "diagnostic\n")
        precondition(log.records[0].duration != nil && log.records[0].paths == [root.path])
        precondition(log.records[0].variant == "test-option")
        let saved = try ExecutionLogStore(directory: root).load()
        precondition(saved == log.records)
        _ = await run(action, record: false)
        precondition(log.records.count == 1)
        print("PASS actual runner persists metadata and both streams; trials excluded")
        action.kind = .runScript(ScriptSpec(inlineSource: "sleep 3", timeoutSeconds: 1))
        let timeout = await run(action)
        precondition(timeout.timedOut && log.records[0].timedOut == true && !log.records[0].success)
        precondition(Notifier.failures == 1)
        print("PASS actual timeout recorded as failure")
        let file = root.appendingPathComponent("execution-log.json")
        try fm.removeItem(at: file)
        try fm.createDirectory(at: file, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: file.appendingPathComponent("keep"))
        log.clear()
        precondition(log.records.count == 2 && log.storageError != nil)
        print("PASS failed clear preserves visible records")
        let corruptRoot = root.appendingPathComponent("corrupt")
        try fm.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corruptFile = corruptRoot.appendingPathComponent("execution-log.json")
        let bytes = Data("invalid history".utf8); try bytes.write(to: corruptFile)
        let corrupt = ExecutionLog(directory: corruptRoot)
        corrupt.append(log.records[0])
        let retained = try Data(contentsOf: corruptFile)
        precondition(retained == bytes)
        precondition(corrupt.storageError != nil && corrupt.records.count == 1)
        corrupt.clear()
        precondition(corrupt.storageError == nil && corrupt.records.isEmpty)
        print("PASS corrupt history retained until explicit clear")
    }
}
