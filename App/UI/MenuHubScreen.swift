// MenuHubScreen.swift — 「右键菜单」集中入口 Hub(主屏)
//
// 精确复刻 docs/design/hifi/screen-menu-preview.jsx 的 ScreenMenuHub:
// 左栏 = 整菜单实时预览(筛选 + 模拟对象,像真实右键菜单的卡片);
// 右栏 = 随选中项类型自适应的详情面板。
//
// 控制程度模型(HANDOFF「核心概念 ●◐○」):
//   ● 自有/扩展包动作 — 可排序·可编辑·可启停(抓手 + 渐变图标 + 开关)
//   ◐ 系统服务/快速操作 — 仅可隐藏(控制点 + 线框图标 + 开关)
//   ○ 第三方扩展     — 仅整体开关(控制点 + 线框图标 + 开关 + 锁)

import SwiftUI
import MenuMateCore

// MARK: - 行高探针(拖拽阈值用实测行高)

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue(); if n > value { value = n }
    }
}

// MARK: - 选中标识(右栏详情据此切换)

enum HubSelection: Equatable {
    case ownAction(UUID)
    case systemService(String)   // ManagedService.id
    case ownExtension(String)    // ManagedExtension.id
}

// MARK: - ScreenMenuHub(主屏)

struct ScreenMenuHub: View {
    @ObservedObject private var state = AppState.shared
    @StateObject private var servicesManager = ServicesManager()
    @StateObject private var extensionManager = ExtensionManager()
    @State private var caps = CapabilityProbe.cachedOrUnknown()

    @State private var filter: Int = 0          // 0 全部 / 1 仅 MenuMate / 2 仅系统
    @State private var simContext: Int = 0       // 0 图片 / 1 文件 / 2 文件夹 / 3 空白处
    @State private var selection: HubSelection?

    // 自定义拖拽重排状态(不用系统 DnD,避免「+」拷贝光标、提供抬起+让位动画)
    @State private var dragID: UUID?            // 正在拖的顶层动作
    @State private var dragStartIndex: Int = 0   // 拖拽开始时在顶层序列中的下标
    @State private var dragTranslation: CGFloat = 0
    @State private var liveOrder: [MenuAction] = []   // 拖拽会话内的实时顺序(不落盘)
    @State private var rowHeight: CGFloat = 25        // 行高(由 PreferenceKey 实测校正)

    private var simCtx: SimContext {
        [SimContext.image, .file, .folder, .empty][simContext]
    }
    private var showMM: Bool { filter != 2 }
    private var showSys: Bool { filter != 1 }

    /// 顶层 + 子菜单,按 sortOrder 排序的自有动作。
    private var sortedActions: [MenuAction] {
        state.config.actions.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 326)
                .background(.regularMaterial)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(MMColor.separator).frame(width: 0.5)
                }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MMColor.content)
        .onAppear {
            servicesManager.reload()
            extensionManager.reload()
            refreshCaps()
            ensureSelection()
        }
        .onChange(of: filter) { _ in ensureSelection() }
        .onChange(of: simContext) { _ in ensureSelection() }
    }

    // MARK: 左栏

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(MMColor.label2)
                    Text(String(localized: "menu.sidebarTitle"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(String(localized: "menu.dragToSortClickToEdit"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(MMColor.label3)
                }
                Segmented([String(localized: "menu.filterAll"), String(localized: "menu.filterMenuMateOnly"), String(localized: "menu.filterSystemOnly")], selection: $filter)
                ContextSim(selection: $simContext)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollView {
                menuPreview
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
            }

            footer
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
            Group {
                if filter == 2 {
                    Legend()
                } else {
                    HStack(spacing: 8) {
                        MMButton(String(localized: "menu.addAction"), systemImage: "plus", size: .sm) { addAction() }
                        Spacer(minLength: 0)
                        Text(String(localized: "menu.realMenuAppearance"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(MMColor.label3)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: 菜单预览卡(对照 MenuPreviewFull)

    private var menuPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 系统区(灰示意,不可交互)
            Text(String(localized: "menu.systemSampleItems"))
                .font(.system(size: 12))
                .foregroundStyle(MMColor.label3)
                .padding(.horizontal, 14)
                .padding(.vertical, 2)

            if showMM { mmSection }
            if showSys { sysSection }
        }
        .padding(.vertical, 6)
        .background(MMColor.content)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
    }

    // MENUMATE 区(●)
    @ViewBuilder private var mmSection: some View {
        let visible = sortedActions.filter { MenuPreviewVisibility.isVisible($0, in: simCtx) }
        let baseTop = visible.filter { $0.placement == .topLevel }
        let sub = visible.filter { $0.placement == .submenu }
        // 拖拽进行中用会话顺序;否则用真实顺序。
        let top = dragID != nil ? liveOrder.filter { a in baseTop.contains(where: { $0.id == a.id }) } : baseTop

        sep
        SectionCap(String(localized: "menu.sectionMenuMateTopLevel"), hint: String(localized: "menu.hintFullControl"))
        ForEach(Array(top.enumerated()), id: \.element.id) { idx, action in
            let isDragging = dragID == action.id
            let currentIndex = top.firstIndex(where: { $0.id == action.id }) ?? idx
            actionRow(action, sub: false)
                .background(GeometryReader { g in
                    Color.clear.preference(key: RowHeightKey.self, value: g.size.height)
                })
                // 被拖行:抬起(放大+阴影+不透明),并相对原位偏移以始终跟随光标。
                .scaleEffect(isDragging ? 1.03 : 1)
                .shadow(color: isDragging ? .black.opacity(0.28) : .clear,
                        radius: isDragging ? 8 : 0, x: 0, y: isDragging ? 4 : 0)
                .offset(y: isDragging
                        ? CGFloat(dragStartIndex - currentIndex) * rowHeight + dragTranslation
                        : 0)
                .zIndex(isDragging ? 1 : 0)
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { value in
                            if dragID == nil {
                                dragID = action.id
                                liveOrder = baseTop
                                dragStartIndex = baseTop.firstIndex(where: { $0.id == action.id }) ?? idx
                            }
                            dragTranslation = value.translation.height
                            let desired = max(0, min(liveOrder.count - 1,
                                dragStartIndex + Int((value.translation.height / rowHeight).rounded())))
                            if let cur = liveOrder.firstIndex(where: { $0.id == action.id }), cur != desired {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                    let moved = liveOrder.remove(at: cur)
                                    liveOrder.insert(moved, at: desired)
                                }
                            }
                        }
                        .onEnded { _ in
                            commitReorder(liveOrder)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                dragID = nil
                                dragTranslation = 0
                            }
                        }
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: top.map(\.id))
        }
        .onPreferenceChange(RowHeightKey.self) { h in
            if h > 1 { rowHeight = h }
        }
        if !sub.isEmpty {
            // 「MenuMate ▸」子菜单父行
            HStack(spacing: 8) {
                Color.clear.frame(width: 13, height: 1)
                AppIcon("line.3.horizontal", size: 17, hue: .blue)
                Text("MenuMate")
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MMColor.label3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            // 子项:左缩进 + 竖线
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sub) { action in
                    actionRow(action, sub: true)
                }
            }
            .padding(.leading, 2)
            .overlay(alignment: .leading) {
                Rectangle().fill(MMColor.separator).frame(width: 1.5)
            }
            .padding(.leading, 22)
            .padding(.trailing, 6)
        }
    }

    // 系统服务区(◐) + 第三方扩展区(○)
    @ViewBuilder private var sysSection: some View {
        sep
        SectionCap(String(localized: "menu.sectionQuickActionsAndServices"), hint: String(localized: "menu.hintHideOnly"))
        if servicesManager.services.isEmpty {
            emptyHint(String(localized: "menu.emptyNoManageableServices"))
        }
        ForEach(servicesManager.services) { service in
            serviceRow(service)
        }

        sep
        SectionCap(String(localized: "menu.sectionOtherExtensions"), hint: String(localized: "menu.hintToggleOnly"))
        if extensionManager.extensions.isEmpty {
            emptyHint(String(localized: "menu.emptyNoThirdPartyExtensions"))
        }
        ForEach(extensionManager.extensions) { ext in
            extensionRow(ext)
        }
    }

    // MARK: 预览行

    private func actionRow(_ action: MenuAction, sub: Bool) -> some View {
        let isSel = selection == .ownAction(action.id)
        // 来自扩展包的动作带来源 Badge(包名,.accent);预设带「预设」灰;自建无 Badge。
        let badge: (String, BadgeTone)?
        if let repo = action.packRepo {
            badge = (packName(repo), .accent)
        } else if action.presetKey != nil {
            badge = (String(localized: "menu.badgePreset"), .gray)
        } else {
            badge = nil
        }
        return TierRow(
            iconSymbol: action.icon.symbolName,
            iconImageName: action.icon.imageFileName,
            hue: hue(for: action),
            title: action.title.isEmpty ? String(localized: "menu.untitledAction") : action.title,
            selected: isSel,
            control: .full,
            glyphMode: false,
            badge: badge,
            showsChevron: action.variants != nil,
            locked: false,
            isOn: Binding(
                get: { action.isEnabled },
                set: { setOwnEnabled($0, action) }
            )
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = .ownAction(action.id) }
    }

    private func serviceRow(_ service: ManagedService) -> some View {
        let isSel = selection == .systemService(service.id)
        return TierRow(
            iconSymbol: "square.grid.2x2",
            hue: .gray,
            title: service.item.menuTitle,
            selected: isSel,
            control: .hide,
            glyphMode: true,
            badge: service.isShortcutBased ? (String(localized: "menu.badgeHideOnly"), .orange) : nil,
            showsChevron: false,
            locked: false,
            isOn: Binding(
                get: { service.enabledInContextMenu },
                set: { servicesManager.setEnabled($0, for: service) }
            )
        )
        .disabled(!caps.pbsReadable || servicesManager.busy)
        .contentShape(Rectangle())
        .onTapGesture { selection = .systemService(service.id) }
    }

    private func extensionRow(_ ext: ManagedExtension) -> some View {
        let isSel = selection == .ownExtension(ext.id)
        return TierRow(
            iconSymbol: "square.stack",
            hue: .gray,
            title: ext.displayName,
            selected: isSel,
            control: .opaque,
            glyphMode: true,
            badge: nil,
            showsChevron: false,
            locked: ext.stuck,
            isOn: Binding(
                get: { ext.info.election == .use },
                set: { extensionManager.setEnabled($0, for: ext) }
            )
        )
        .disabled(!caps.pluginkitAvailable)
        .contentShape(Rectangle())
        .onTapGesture { selection = .ownExtension(ext.id) }
    }

    // MARK: 右栏(自适应详情)

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            ScrollView {
                detailPanel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            // 系统服务 / 第三方扩展选中时,底部出现维护底栏。
            if isSystemSelection {
                VStack(spacing: 0) {
                    Rectangle().fill(MMColor.separator).frame(height: 0.5)
                    HStack(spacing: 8) {
                        MMButton(String(localized: "menu.refresh"), systemImage: "arrow.clockwise", size: .sm) {
                            servicesManager.reload()
                            extensionManager.reload()
                            refreshCapsForce()
                        }
                        MMButton(String(localized: "menu.restartFinderToApply"), kind: .tinted, size: .sm) {
                            servicesManager.restartFinder()
                        }
                        Spacer(minLength: 0)
                        if servicesManager.hasBackup {
                            MMButton(String(localized: "menu.restorePbsBackup"), kind: .danger, size: .sm) {
                                servicesManager.restoreBackup()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var isSystemSelection: Bool {
        switch selection {
        case .systemService, .ownExtension: return true
        default: return false
        }
    }

    @ViewBuilder private var detailPanel: some View {
        switch selection {
        case .ownAction(let id):
            if let action = state.config.actions.first(where: { $0.id == id }) {
                if action.packID != nil {
                    packPanel(for: action)
                        .id(id)
                } else {
                    PvEditor(action: action,
                             onSave: { saveAction($0) },
                             onRestore: action.presetKey != nil ? { restorePreset(action) } : nil,
                             onDelete: { deleteAction(action) })
                        .id(id)   // 切换动作时重建,刷新本地编辑态
                }
            } else {
                placeholder
            }
        case .systemService(let id):
            if let service = servicesManager.services.first(where: { $0.id == id }) {
                PvSystemPanel(
                    service: service,
                    isOn: Binding(
                        get: { service.enabledInContextMenu },
                        set: { servicesManager.setEnabled($0, for: service) }
                    ),
                    toggleEnabled: caps.pbsReadable && !servicesManager.busy)
            } else {
                placeholder
            }
        case .ownExtension(let id):
            if let ext = extensionManager.extensions.first(where: { $0.id == id }) {
                PvOpaquePanel(
                    ext: ext,
                    isOn: Binding(
                        get: { ext.info.election == .use },
                        set: { extensionManager.setEnabled($0, for: ext) }
                    ),
                    toggleEnabled: caps.pluginkitAvailable)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 28))
                .foregroundStyle(MMColor.label3)
            Text(String(localized: "menu.placeholderSelectToView"))
                .font(.system(size: 12.5))
                .foregroundStyle(MMColor.label2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: 小部件

    private var sep: some View {
        Rectangle().fill(MMColor.separator)
            .frame(height: 0.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(MMColor.label3)
            .padding(.horizontal, 14)
            .padding(.vertical, 3)
    }

    // MARK: 行为

    private func hue(for action: MenuAction) -> AppIconHue {
        // 用户自定义配色优先。
        if let raw = action.iconHue, let h = AppIconHue(rawValue: raw) { return h }
        // 扩展包动作统一用 teal(与 PvPackPanel / PackRow 一致)。
        if action.packID != nil { return .teal }
        // 简单按预设 key / 标题派生稳定色,无映射时落 gray。
        switch action.presetKey {
        case "open-editor": return .blue
        case "image-convert": return .purple
        case "open-terminal": return .gray
        default: break
        }
        if case .openWith = action.kind { return .blue }
        return .gray
    }

    /// 扩展包动作详情:PvPackPanel 接真实数据,菜单标题/位置可改并写回。
    private func packPanel(for action: MenuAction) -> some View {
        PvPackPanel(
            action: action,
            packName: action.packID.flatMap { key in
                state.packManager.packs.first(where: { $0.key == key })?.manifest.name
            } ?? action.packRepo.map(packName) ?? String(localized: "menu.packFallbackName"),
            onSave: { saveAction($0) })
    }

    /// owner/repo 取末段作为包名兜底显示(无安装记录时)。
    private func packName(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    /// 拖拽结束:把拖拽会话的顶层顺序落盘。
    /// 注意 liveOrder 只含「当前模拟对象下可见」的顶层动作;为不打乱被过滤掉的隐藏动作,
    /// 按可见序列的相对顺序重排,再把全部顶层动作连续重编 sortOrder。
    private func commitReorder(_ order: [MenuAction]) {
        guard !order.isEmpty else { return }
        var config = state.config
        let orderIDs = order.map(\.id)
        // 全部顶层动作(含当前不可见的),按原 sortOrder。
        var allTop = config.actions
            .filter { $0.placement == .topLevel }
            .sorted { $0.sortOrder < $1.sortOrder }
        // 把可见动作按新顺序重新落位,隐藏动作保持相对位置。
        var queue = orderIDs
        allTop = allTop.map { a in
            if orderIDs.contains(a.id) {
                let nextID = queue.removeFirst()
                return config.actions.first(where: { $0.id == nextID }) ?? a
            }
            return a
        }
        for (i, a) in allTop.enumerated() {
            if let idx = config.actions.firstIndex(where: { $0.id == a.id }) {
                config.actions[idx].sortOrder = i
            }
        }
        state.update(config)
    }

    private func setOwnEnabled(_ value: Bool, _ action: MenuAction) {
        var config = state.config
        guard let idx = config.actions.firstIndex(where: { $0.id == action.id }) else { return }
        config.actions[idx].isEnabled = value
        state.update(config)
    }

    private func saveAction(_ saved: MenuAction) {
        var config = state.config
        if let idx = config.actions.firstIndex(where: { $0.id == saved.id }) {
            config.actions[idx] = saved
        } else {
            config.actions.append(saved)
        }
        state.update(config)
    }

    private func addAction() {
        let new = MenuAction(
            id: UUID(), title: String(localized: "menu.newActionDefaultTitle"), icon: .symbol("bolt"),
            kind: .runScript(ScriptSpec()), matching: MatchRule(),
            placement: .topLevel, isEnabled: true,
            sortOrder: (state.config.actions.map(\.sortOrder).max() ?? 0) + 1)
        saveAction(new)
        selection = .ownAction(new.id)
    }

    private func deleteAction(_ action: MenuAction) {
        // 从配置移除该动作(自有动作彻底删除;预设删除靠 MMSeededPresetKeys 墓碑"粘住",
        // 不会下次启动被补回,可用「恢复出厂预设」找回)。脚本文件保留;孤儿图标由 update() 的 GC 清理。
        var config = state.config
        config.actions.removeAll { $0.id == action.id }
        state.update(config)
        selection = nil   // ensureSelection 兜底重选
    }

    private func restorePreset(_ action: MenuAction) {
        // 恢复单条预设:只重落该预设的出厂脚本 + 把该动作重置为出厂态(保留它的位置与启用状态),
        // 不影响其他预设与用户自建动作。
        guard let key = action.presetKey else { return }
        PresetSeeder.restorePreset(presetKey: key, state: AppState.shared)
    }

    /// 选中态兜底:默认选中第一个自有动作(尊重当前筛选 / 模拟对象)。
    private func ensureSelection() {
        if let sel = selection, selectionStillValid(sel) { return }
        if showMM {
            let visible = sortedActions.filter { MenuPreviewVisibility.isVisible($0, in: simCtx) }
            if let first = visible.first {
                selection = .ownAction(first.id)
                return
            }
        }
        if showSys {
            if let first = servicesManager.services.first {
                selection = .systemService(first.id)
                return
            }
            if let first = extensionManager.extensions.first {
                selection = .ownExtension(first.id)
                return
            }
        }
        selection = nil
    }

    private func selectionStillValid(_ sel: HubSelection) -> Bool {
        switch sel {
        case .ownAction(let id):
            guard showMM, let a = state.config.actions.first(where: { $0.id == id }) else { return false }
            return MenuPreviewVisibility.isVisible(a, in: simCtx)
        case .systemService(let id):
            return showSys && servicesManager.services.contains { $0.id == id }
        case .ownExtension(let id):
            return showSys && extensionManager.extensions.contains { $0.id == id }
        }
    }

    private func refreshCaps() {
        Task {
            let c = await Task.detached { CapabilityProbe.current() }.value
            await MainActor.run { caps = c }
        }
    }

    private func refreshCapsForce() {
        Task {
            let c = await Task.detached { CapabilityProbe.reprobe() }.value
            await MainActor.run { caps = c }
        }
    }
}

// MARK: - ContextSim(模拟右键对象)

struct ContextSim: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(localized: "menu.simContextLabel"))
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(MMColor.label2)
            Segmented([String(localized: "menu.simImage"), String(localized: "menu.simFile"), String(localized: "menu.simFolder"), String(localized: "menu.simEmpty")], selection: $selection)
        }
    }
}

// MARK: - SectionCap(预览区段小标题)

struct SectionCap: View {
    let title: String
    var hint: String?

    init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(MMColor.label3)
            if let hint {
                Text(hint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(MMColor.label4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 3)
        .padding(.top, 2)
    }
}

// MARK: - TierRow(通用预览行)
//
// 对照 jsx TierRow:ctrl=full 用抓手 / 否则用控制点;
// glyphMode 用线框单色图标,否则渐变 AppIcon;行尾开关。

struct TierRow: View {
    let iconSymbol: String
    /// 非空时渲染用户导入的自定义图片图标(走 ActionIconView 图片分支),替代 iconSymbol。
    var iconImageName: String? = nil
    var hue: AppIconHue = .gray
    let title: String
    var selected: Bool = false
    var control: ControlDegree = .full
    var glyphMode: Bool = false
    var badge: (String, BadgeTone)?
    var showsChevron: Bool = false
    var locked: Bool = false
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            // 行首:full 用抓手,其余用控制点(居中固定宽 13)
            if control == .full {
                Grip()
                    .frame(width: 13)
            } else {
                ControlDot(control)
                    .frame(width: 13)
            }

            // 图标:glyph 线框 / 用户图片 / 渐变方
            if glyphMode {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(MMColor.label4, lineWidth: 1)
                    Image(systemName: iconSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(MMColor.label3)
                }
                .frame(width: 17, height: 17)
            } else if let iconImageName {
                ActionIconView(icon: .imageFile(iconImageName), hue: selected ? .gray : hue, size: 17)
            } else {
                AppIcon(iconSymbol, size: 17, hue: selected ? .gray : hue)
            }

            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : MMColor.label)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(selected ? Color.white : MMColor.label3)
            }
            if let badge {
                Badge(badge.0, tone: selected ? .gray : badge.1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : MMColor.label3)
            }
            MMSwitch($isOn, scale: 0.56)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? MMColor.accent : Color.clear)
                .padding(.horizontal, 6)
        )
        .opacity(isOn ? 1 : 0.55)
    }
}

// MARK: - Legend(可控程度图例)

struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(.full, String(localized: "menu.legendFull"))
            row(.hide, String(localized: "menu.legendHide"))
            row(.opaque, String(localized: "menu.legendOpaque"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.content)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.5)
        )
    }

    private func row(_ kind: ControlDegree, _ text: String) -> some View {
        HStack(spacing: 5) {
            ControlDot(kind, size: 9)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(MMColor.label2)
        }
    }
}

