import Foundation
import MenuMateCore

final class ActionRunner: ActionRunning {
    private static let queue = DispatchQueue(label: "com.menumate.action-runner", qos: .userInitiated)

    @MainActor
    func run(action: MenuAction, variant: String?, urls: [URL]) {
        let title = action.title
        let kind = action.kind
        let paths = urls.map(\.path)
        let cwd = urls.first.map { url -> URL in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue ? url : url.deletingLastPathComponent()
        }
        let scriptBase = AppPaths.configDirectory()
        var extraEnv = ["MENUMATE_TEMPLATES": AppPaths.templatesDirectory().path,
                        "MENUMATE_DATA": AppPaths.dataDirectory().path]
        // 用户在「通用」选的默认终端/编辑器(bundle id);未选则不注入,脚本用内置默认。
        if let term = AppPrefs.terminalBundleID { extraEnv["MENUMATE_TERMINAL"] = term }
        if let editor = AppPrefs.editorBundleID { extraEnv["MENUMATE_EDITOR"] = editor }

        // 串行队列：保证动作按派发顺序执行（cut 必先于 paste 写完 cutbuffer），
        // 且不占用 Swift 协作线程池（ShellRunner 同步阻塞最长到 timeoutSeconds）。
        // 代价：队头阻塞——一个 60s 的转换会延后后续动作，对 v1 来说这种可预测性是可接受的。
        Self.queue.async {
            let outcome = Self.execute(kind: kind, variant: variant, paths: paths,
                                       scriptBase: scriptBase, cwd: cwd, extraEnv: extraEnv)
            Task { @MainActor in
                ExecutionLog.shared.append(title: title, outcome: outcome)
                if case .failure(let message) = outcome { Notifier.showFailure(title, message) }
            }
        }
    }

    private static func execute(kind: MenuAction.Kind, variant: String?, paths: [String],
                                scriptBase: URL, cwd: URL?, extraEnv: [String: String]) -> ExecutionOutcome {
        switch kind {
        case .runScript(let spec):
            let r = ShellRunner.runScript(spec, paths: paths, variant: variant,
                                          scriptBase: scriptBase, cwd: cwd, extraEnv: extraEnv)
            if r.timedOut { return .failure(message: String(format: String(localized: "runtime.timeout"), spec.timeoutSeconds)) }
            if r.exitCode != 0 { return .failure(message: "exit \(r.exitCode): \(r.stderr)") }
            // stdout 首行作为成功摘要（脚本环境契约）
            let summary = r.stdout.split(separator: "\n").first.map(String.init)
            return .success(summary: summary)
        case .openWith(let bundleID):
            let r = ShellRunner.run("/usr/bin/open", ["-b", bundleID] + paths, timeout: 15)
            return r.exitCode == 0 ? .success(summary: nil) : .failure(message: r.stderr)
        }
    }
}
