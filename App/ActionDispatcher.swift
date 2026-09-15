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
        guard !AppState.shared.storageRecoveryRequired,
              request.paths.count <= IPC.maxPaths,
              let action = AppState.shared.config.actions.first(where: { $0.id == request.actionID }),
              action.isEnabled else { return }
        let urls = request.paths.map { URL(fileURLWithPath: $0) }
        // 接受符号链接：脚本拿到的是符号链接路径本身，与 Finder 呈现选中项的方式一致；不是越权（用户脚本本就有用户的文件权限）
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        let context: MatchContext
        if action.matching.targets == .container {
            guard urls.count == 1, let url = urls.first else { return }
            context = .container(url)
        } else { context = .items(urls) }
        guard RuleMatcher.matches(rule: action.matching, context: context) else { return }
        switch action.variants {
        case .fixed(let values): guard let variant = request.variant, values.contains(variant) else { return }
        case .directoryListing(let path):
            let directory = path.hasPrefix("/") ? URL(fileURLWithPath: path) : AppPaths.configDirectory().appendingPathComponent(path)
            guard let variant = request.variant, TemplateStore.list(in: directory).contains(variant) else { return }
        case nil: guard request.variant == nil else { return }
        }
        if action.interface != nil {
            ActionWindowController.present(action: action, variant: request.variant, urls: urls)
            return
        }
        runner.run(action: action, variant: request.variant, urls: urls)
    }
}
