import Foundation
import MenuMateCore

final class ActionRunner: ActionRunning {
    private static let queue = DispatchQueue(label: "com.menumate.action-runner", qos: .userInitiated)

    /// 执行环境契约的非选中相关部分(模板/数据目录 + 用户选的终端/编辑器)。
    /// 抽出来供真实执行与编辑器「试运行」共用,保证两者环境一致、不漂移。
    static func contractEnv() -> [String: String] {
        var env = ["MENUMATE_INPUT": "{}",
                   "MENUMATE_LOCALE": Bundle.main.preferredLocalizations.first ?? "en",
                   "MENUMATE_TEMPLATES": AppPaths.templatesDirectory().path,
                   "MENUMATE_DATA": AppPaths.dataDirectory().path]
        if let term = AppPrefs.terminalBundleID { env["MENUMATE_TERMINAL"] = term }
        if let editor = AppPrefs.editorBundleID { env["MENUMATE_EDITOR"] = editor }
        return env
    }

    /// cwd = 第一个选中项的所在文件夹(若它本身是文件夹,则取它自己),与 Finder 一致。
    static func workingDirectory(for urls: [URL]) -> URL? {
        urls.first.map { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? url : url.deletingLastPathComponent()
        }
    }

    @MainActor
    func run(action: MenuAction, variant: String?, urls: [URL]) {
        runWithResult(action: action, variant: variant, urls: urls) { _ in }
    }

    @MainActor
    func runWithResult(action: MenuAction, variant: String?, urls: [URL],
                       environment: [String: String] = [:], cwdOverride: URL? = nil,
                       recordExecution: Bool = true,
                       completion: @escaping @MainActor (ShellResult) -> Void) {
        guard !AppState.shared.storageRecoveryRequired else {
            completion(ShellResult(exitCode: -1, stdout: "", stderr: String(localized: "runtime.storageBlocked"), timedOut: false))
            return
        }
        PackUsage.retain(action.packID)
        let title = action.displayTitle
        let kind = action.kind
        let paths = urls.map(\.path)
        let cwd = cwdOverride ?? Self.workingDirectory(for: urls)
        let scriptBase = AppPaths.configDirectory()
        let extraEnv = Self.contractEnv().merging(environment) { _, override in override }

        // 串行队列：保证动作按派发顺序执行（cut 必先于 paste 写完 cutbuffer），
        // 且不占用 Swift 协作线程池（ShellRunner 同步阻塞最长到 timeoutSeconds）。
        // 代价：队头阻塞——一个 60s 的转换会延后后续动作，对 v1 来说这种可预测性是可接受的。
        Self.queue.async {
            let started = ProcessInfo.processInfo.systemUptime
            let result = Self.executeRaw(kind: kind, variant: variant, paths: paths,
                                         scriptBase: scriptBase, cwd: cwd, extraEnv: extraEnv)
            let record = ExecutionRecord(title: title, paths: paths, variant: variant, result: result,
                                         duration: ProcessInfo.processInfo.systemUptime - started)
            Task { @MainActor in
                PackUsage.release(action.packID)
                if recordExecution {
                    ExecutionLog.shared.append(record)
                    if !record.success {
                        let message = result.timedOut ? String(localized: "editor.testRunTimedOut")
                            : "exit \(result.exitCode): \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                        Notifier.showFailure(title, message)
                    }
                }
                completion(result)
            }
        }
    }

    private static func executeRaw(kind: MenuAction.Kind, variant: String?, paths: [String],
                                   scriptBase: URL, cwd: URL?, extraEnv: [String: String]) -> ShellResult {
        switch kind {
        case .runScript(let spec):
            return ShellRunner.runScript(spec, paths: paths, variant: variant,
                                         scriptBase: scriptBase, cwd: cwd, extraEnv: extraEnv)
        case .openWith(let bundleID):
            return ShellRunner.run("/usr/bin/open", ["-b", bundleID] + paths, timeout: 15)
        }
    }

}
