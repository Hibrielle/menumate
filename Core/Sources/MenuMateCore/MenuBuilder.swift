import Foundation

public struct MenuItemSpec: Equatable {
    public var title: String
    public var symbol: String?
    public var request: ActionRequest?
    public var children: [MenuItemSpec]

    public init(title: String, symbol: String?, request: ActionRequest?, children: [MenuItemSpec] = []) {
        self.title = title; self.symbol = symbol; self.request = request; self.children = children
    }
}

public struct MenuBuildInput {
    public var config: MenuConfig
    public var context: MatchContext
    public var heartbeatFresh: Bool
    public var variantListings: [UUID: [String]]   // directoryListing 类动作的预解析结果

    public init(config: MenuConfig, context: MatchContext, heartbeatFresh: Bool,
                variantListings: [UUID: [String]]) {
        self.config = config; self.context = context
        self.heartbeatFresh = heartbeatFresh; self.variantListings = variantListings
    }
}

public enum MenuBuilder {
    /// 预解析 directoryListing 类 variants（base = 配置目录）。
    /// 对所有 enabled 的目录列举动作解析——快照要覆盖一切上下文，不能按 context 裁剪。
    public static func prepareListings(config: MenuConfig, base: URL) -> [UUID: [String]] {
        var result: [UUID: [String]] = [:]
        for action in config.actions {
            guard action.isEnabled,
                  case .directoryListing(let path) = action.variants else { continue }
            let dir = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                                          : base.appendingPathComponent(path)
            result[action.id] = TemplateStore.list(in: dir)
        }
        return result
    }

    public static func build(_ input: MenuBuildInput) -> [MenuItemSpec] {
        guard input.heartbeatFresh else { return [] }
        var top: [MenuItemSpec] = []
        var grouped: [MenuItemSpec] = []
        for action in RuleMatcher.visibleActions(in: input.config, context: input.context) {
            guard let spec = spec(for: action, input: input) else { continue }
            // "MenuMate" 分组节点固定排在最后；sortOrder 只决定各层内部顺序
            if action.placement == .submenu { grouped.append(spec) } else { top.append(spec) }
        }
        if !grouped.isEmpty {
            top.append(MenuItemSpec(title: "MenuMate", symbol: nil, request: nil, children: grouped))
        }
        return top
    }

    private static func spec(for action: MenuAction, input: MenuBuildInput) -> MenuItemSpec? {
        let symbol: String?
        if case .symbol(let s) = action.icon { symbol = s } else { symbol = nil }   // imageFile 图标渲染推迟到 v2；v1 仅 SF Symbol
        let variantValues: [String]?
        switch action.variants {
        case .fixed(let list): variantValues = list
        case .directoryListing:
            // [] 含义二选一：(a) 调用方没为该动作跑 prepareListings (b) 目录确实为空。两者都整体隐藏该动作。
            // 调用方必须用同一份 config 先调 prepareListings(config:base:) 再调 build()。
            variantValues = input.variantListings[action.id] ?? []
        case nil: variantValues = nil
        }
        if let values = variantValues {
            guard !values.isEmpty else { return nil }   // 无可选子项 → 整体隐藏
            let children = values.map {
                MenuItemSpec(title: $0, symbol: nil,
                             // paths 由 FinderSync 消费方在派发前回填选中路径（见 Task 13）
                             request: ActionRequest(actionID: action.id, variant: $0, paths: []))
            }
            return MenuItemSpec(title: action.title, symbol: symbol, request: nil, children: children)
        }
        return MenuItemSpec(title: action.title, symbol: symbol,
                            // paths 由 FinderSync 消费方在派发前回填选中路径（见 Task 13）
                            request: ActionRequest(actionID: action.id, variant: nil, paths: []))
    }
}
