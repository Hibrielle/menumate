import Foundation
import MenuMateCore

protocol ActionRunning {
    @MainActor func run(action: MenuAction, variant: String?, urls: [URL])
}

@MainActor
final class ActionDispatcher {
    static let shared = ActionDispatcher()
    var runner: ActionRunning = ActionRunner()

    /// 安全闸门：通知载荷不可信。只认本地配置里存在且启用的 actionID，
    /// 路径数量有上限且必须真实存在；脚本内容永远来自本地配置/本地脚本文件。
    func dispatch(_ request: ActionRequest) {
        guard request.paths.count <= IPC.maxPaths,
              let action = AppState.shared.config.actions.first(where: { $0.id == request.actionID }),
              action.isEnabled else { return }
        let urls = request.paths.map { URL(fileURLWithPath: $0) }
        // 接受符号链接：脚本拿到的是符号链接路径本身，与 Finder 呈现选中项的方式一致；不是越权（用户脚本本就有用户的文件权限）
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        runner.run(action: action, variant: request.variant, urls: urls)
    }
}
