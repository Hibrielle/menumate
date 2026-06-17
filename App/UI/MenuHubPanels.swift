// MenuHubPanels.swift — 右键菜单 Hub 右栏的自适应详情面板
//
// 对照 screen-menu-preview.jsx:
//   PvEditor      自有动作详情(真正可编辑并写回 AppState.update())
//   PvPackPanel   扩展包动作详情(只读脚本;本期无 pack 数据,组件备用于 Task 20/21)
//   PvSystemPanel 系统服务详情(仅可隐藏)
//   PvOpaquePanel 第三方扩展详情(不可预览)
//   PanelCard     PvSystem/PvOpaque 共享外壳

import SwiftUI
import AppKit
import MenuMateCore

private let kHairline: CGFloat = 0.5

// MARK: - PvField(右对齐 70 标签 + 内容 + 可选 hint)

struct PvField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MMColor.label2)
                .frame(width: 70, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                content
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(MMColor.label3)
                }
            }
        }
    }
}

// MARK: - PvEditor(自有动作详情,真正可编辑)
//
// 字段逻辑迁移自原 ActionsTab.ActionEditor;此处为常驻内联编辑器,
// 每次字段改动即写回 AppState.update()。

struct PvEditor: View {
    let onSave: (MenuAction) -> Void
    let onRestore: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var action: MenuAction
    @State private var confirmDelete = false
    @State private var kindChoice = 0           // 0 脚本文件 1 内联脚本 2 用 App 打开
    @State private var scriptPath = ""
    @State private var inlineSource = ""
    @State private var appBundleID = ""
    @State private var utisText = ""
    @State private var targetChoice = 0          // 0 文件和文件夹 1 仅文件 2 仅文件夹 3 目录空白处
    @State private var minSelText = ""           // 最少选中数（空=不限）
    @State private var maxSelText = ""           // 最多选中数（空=不限）
    @State private var placementChoice = 0       // 0 菜单顶层 1 子菜单
    @State private var variantChoice = 0         // 0 无 1 固定列表 2 目录列举
    @State private var variantsFixed = ""
    @State private var variantsDir = ""
    @State private var timeoutSeconds = 60
    @State private var loaded = false
    @State private var pendingCommit: DispatchWorkItem?
    @State private var testRunning = false
    @State private var testRunResult: TestRunOutcome?
    @State private var testTask: Task<Void, Never>?

    init(action: MenuAction, onSave: @escaping (MenuAction) -> Void,
         onRestore: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self._action = State(initialValue: action)
        self.onSave = onSave
        self.onRestore = onRestore
        self.onDelete = onDelete
    }

    private var hue: AppIconHue {
        // 用户自定义配色优先。
        if let raw = action.iconHue, let h = AppIconHue(rawValue: raw) { return h }
        switch action.presetKey {
        case "open-editor": return .blue
        case "image-convert": return .purple
        default: break
        }
        if case .openWith = action.kind { return .blue }
        return .gray
    }

    private var subtitle: String {
        let placeText = placementChoice == 1 ? String(localized: "editor.placeSubmenuShort") : String(localized: "editor.placeTopLevelShort")
        return action.presetKey != nil
            ? String(format: String(localized: "editor.subtitleFactoryPreset"), placeText)
            : String(format: String(localized: "editor.subtitleCustomAction"), placeText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            // 头部
            HStack(spacing: 11) {
                ActionIconView(icon: action.icon, hue: hue, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(action.title.isEmpty ? String(localized: "editor.untitledAction") : action.title)
                            .font(.system(size: 15.5, weight: .semibold))
                        if action.presetKey != nil {
                            Badge(String(localized: "editor.presetBadge"))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(MMColor.label2)
                }
                Spacer(minLength: 0)
                MMSwitch(Binding(get: { action.isEnabled }, set: { action.isEnabled = $0; commit() }))
            }

            VStack(alignment: .leading, spacing: 11) {
                PvField(String(localized: "editor.menuTitle")) {
                    MMField(Binding(get: { action.title }, set: { action.title = $0; commit() }),
                            placeholder: String(localized: "editor.menuTitle"), width: 200)
                }
                PvField(String(localized: "editor.icon")) {
                    IconPickerField(
                        icon: Binding(get: { action.icon },
                                      set: { action.icon = $0; commit() }),
                        hue: Binding(get: { hue },
                                     set: { action.iconHue = $0.rawValue; commit() })
                    )
                }
                PvField(String(localized: "editor.type")) {
                    Segmented([String(localized: "editor.typeScriptFile"), String(localized: "editor.typeInlineScript"), String(localized: "editor.typeOpenWithApp")], selection: $kindChoice)
                        .frame(width: 240)
                        .onChange(of: kindChoice) { _ in commit() }
                }

                // 类型相关字段
                if kindChoice == 0 {
                    PvField(String(localized: "editor.scriptPath"), hint: String(localized: "editor.scriptPathHint")) {
                        HStack(spacing: 8) {
                            MMField($scriptPath, mono: true, width: 200)
                                .onChange(of: scriptPath) { _ in commit() }
                            MMButton(String(localized: "editor.choose"), size: .sm) { chooseScript() }
                        }
                    }
                } else if kindChoice == 1 {
                    PvField(String(localized: "editor.typeInlineScript"), hint: String(localized: "editor.inlineScriptHint")) {
                        TextEditor(text: $inlineSource)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 240, height: 72)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(MMColor.field)
                            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                                    .stroke(MMColor.border, lineWidth: kHairline)
                            )
                            .onChange(of: inlineSource) { _ in commit() }
                    }
                } else {
                    PvField(String(localized: "editor.appBundleID")) {
                        HStack(spacing: 8) {
                            MMField($appBundleID, mono: true, width: 200)
                                .onChange(of: appBundleID) { _ in commit() }
                            MMButton(String(localized: "editor.chooseApp"), size: .sm) { chooseApp() }
                        }
                    }
                }

                PvField(String(localized: "editor.target")) {
                    targetPopup
                }
                // 选中数范围对「目录空白处」无意义(那里没有选中项),仅在针对选中项时显示。
                if targetChoice != 3 {
                    PvField(String(localized: "editor.selectionCount"), hint: String(localized: "editor.selectionCountHint")) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(String(localized: "editor.selMin")).font(.system(size: 12)).foregroundStyle(MMColor.label2)
                                selCountField($minSelText)
                                Text(String(localized: "editor.selMax")).font(.system(size: 12)).foregroundStyle(MMColor.label2)
                                selCountField($maxSelText)
                            }
                            if selCountInvalid {
                                Text(String(localized: "editor.selectionCountInvalid"))
                                    .font(.system(size: 11)).foregroundStyle(MMColor.red)
                            }
                        }
                    }
                }
                PvField(String(localized: "editor.restrictType"), hint: String(localized: "editor.restrictTypeHint")) {
                    VStack(alignment: .leading, spacing: 6) {
                        TypeCategoryChips(utisText: $utisText)
                        MMField($utisText, mono: true, width: 240)
                            .onChange(of: utisText) { _ in commit() }
                    }
                }
                PvField(String(localized: "editor.placement")) {
                    placementPopup
                }
                PvField(String(localized: "editor.submenuExpand")) {
                    HStack(spacing: 8) {
                        variantPopup
                        if variantChoice == 1, !variantsFixed.isEmpty {
                            Text(variantsFixed.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(MMColor.label2)
                        }
                    }
                }
                if variantChoice == 1 {
                    PvField(String(localized: "editor.fixedItems"), hint: String(localized: "editor.fixedItemsHint")) {
                        MMField($variantsFixed, mono: true, width: 200)
                            .onChange(of: variantsFixed) { _ in commit() }
                    }
                } else if variantChoice == 2 {
                    PvField(String(localized: "editor.listDirectory"), hint: String(localized: "editor.listDirectoryHint")) {
                        MMField($variantsDir, mono: true, width: 200)
                            .onChange(of: variantsDir) { _ in commit() }
                    }
                }
                if kindChoice < 2 {
                    PvField(String(localized: "editor.timeout")) {
                        HStack(spacing: 6) {
                            TextField("", value: $timeoutSeconds, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .frame(width: 56)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(MMColor.field)
                                .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                                    .stroke(MMColor.border, lineWidth: kHairline))
                                .onChange(of: timeoutSeconds) { _ in commit() }
                            Text(String(localized: "editor.seconds")).font(.system(size: 12)).foregroundStyle(MMColor.label2)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if kindChoice == 0 {
                    MMButton(String(localized: "editor.openScriptInEditor"), systemImage: "chevron.left.forwardslash.chevron.right", size: .sm) {
                        openScriptInEditor()
                    }
                }
                if kindChoice < 2 {   // 仅脚本类(文件 / 内联)可试运行
                    MMButton(testRunning ? String(localized: "editor.testRunRunning") : String(localized: "editor.testRun"),
                             systemImage: "play", size: .sm) { testRun() }
                        .disabled(testRunning)
                }
                Spacer(minLength: 0)
                if onDelete != nil {
                    MMButton(String(localized: "editor.delete"), kind: .danger, size: .sm) { confirmDelete = true }
                }
                if let onRestore {
                    MMButton(String(localized: "editor.restorePreset"), size: .sm) { onRestore() }
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear(perform: loadFromAction)
        .onDisappear { flushCommit(); testTask?.cancel() }
        .sheet(item: $testRunResult) { TestRunSheet(outcome: $0) }
        .alert(action.presetKey != nil
               ? String(format: String(localized: "editor.deletePresetConfirm"), action.title)
               : String(format: String(localized: "editor.deleteActionConfirm"), action.title),
               isPresented: $confirmDelete) {
            Button(String(localized: "editor.deleteConfirm"), role: .destructive) { onDelete?() }
            Button(String(localized: "editor.cancel"), role: .cancel) {}
        } message: {
            Text(action.presetKey != nil
                 ? String(localized: "editor.deletePresetMessage")
                 : String(localized: "editor.deleteActionMessage"))
        }
    }

    /// 最少 > 最多 → 该动作永不出现,给个明确警告。
    private var selCountInvalid: Bool {
        guard let mn = Int(minSelText.trimmingCharacters(in: .whitespaces)), mn > 0,
              let mx = Int(maxSelText.trimmingCharacters(in: .whitespaces)), mx > 0 else { return false }
        return mn > mx
    }

    // 小号数字输入框：空 = 不限。沿用 timeout 字段外观。
    private func selCountField(_ binding: Binding<String>) -> some View {
        TextField(String(localized: "editor.selAny"), text: binding)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .frame(width: 44)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(MMColor.field)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                .stroke(MMColor.border, lineWidth: kHairline))
            .onChange(of: binding.wrappedValue) { _ in commit() }
    }

    // MARK: 弹出选择(Menu 驱动真实交互,外观对照 MMPopup)

    private var targetPopup: some View {
        let labels = [String(localized: "editor.targetFilesAndFolders"), String(localized: "editor.targetFilesOnly"), String(localized: "editor.targetFoldersOnly"), String(localized: "editor.targetContainer")]
        return Menu {
            ForEach(labels.indices, id: \.self) { i in
                Button(labels[i]) { targetChoice = i; commit() }
            }
        } label: {
            MMPopup(labels[targetChoice], width: 150)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var placementPopup: some View {
        let labels = [String(localized: "editor.placeTopLevel"), String(localized: "editor.placeSubmenu")]
        return Menu {
            ForEach(labels.indices, id: \.self) { i in
                Button(labels[i]) { placementChoice = i; commit() }
            }
        } label: {
            MMPopup(labels[placementChoice], width: 180)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var variantPopup: some View {
        let labels = [String(localized: "editor.variantNone"), String(localized: "editor.variantFixedList"), String(localized: "editor.variantDirectoryListing")]
        return Menu {
            ForEach(labels.indices, id: \.self) { i in
                Button(labels[i]) { variantChoice = i; commit() }
            }
        } label: {
            MMPopup(labels[variantChoice], width: 120)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: 载入 / 提交

    private func loadFromAction() {
        switch action.kind {
        case .runScript(let spec):
            timeoutSeconds = spec.timeoutSeconds
            if let p = spec.scriptPath { kindChoice = 0; scriptPath = p }
            else { kindChoice = 1; inlineSource = spec.inlineSource ?? "" }
        case .openWith(let id):
            kindChoice = 2; appBundleID = id
        }
        utisText = action.matching.utis.joined(separator: ", ")
        minSelText = action.matching.minSelectionCount.map(String.init) ?? ""
        maxSelText = action.matching.maxSelectionCount.map(String.init) ?? ""
        targetChoice = [TargetKind.any, .files, .folders, .container].firstIndex(of: action.matching.targets) ?? 0
        placementChoice = action.placement == .submenu ? 1 : 0
        switch action.variants {
        case .fixed(let list): variantChoice = 1; variantsFixed = list.joined(separator: ", ")
        case .directoryListing(let dir): variantChoice = 2; variantsDir = dir
        case nil: variantChoice = 0
        }
        loaded = true
    }

    /// 防抖:编辑器原来每个键击都写盘 + 重推快照。合并 0.3s 内的连续改动;
    /// 切换动作/关闭面板(视图消失)时 flush,保证不丢最后一次输入。
    private func commit() {
        guard loaded else { return }
        pendingCommit?.cancel()
        let work = DispatchWorkItem { performCommit() }
        pendingCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func flushCommit() {
        guard let w = pendingCommit else { return }
        w.cancel()
        pendingCommit = nil
        performCommit()
    }

    private func performCommit() {
        guard loaded else { return }
        pendingCommit = nil
        var saved = action
        switch kindChoice {
        case 0: saved.kind = .runScript(ScriptSpec(scriptPath: scriptPath, timeoutSeconds: timeoutSeconds))
        case 1: saved.kind = .runScript(ScriptSpec(inlineSource: inlineSource, timeoutSeconds: timeoutSeconds))
        default: saved.kind = .openWith(appBundleID: appBundleID)
        }
        saved.matching.utis = utisText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        saved.matching.targets = [TargetKind.any, .files, .folders, .container][targetChoice]
        // 空/非正整数 = 不限;「目录空白处」无选中项,清空两者。
        func parseCount(_ s: String) -> Int? {
            guard let n = Int(s.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
            return n
        }
        if targetChoice == 3 {
            saved.matching.minSelectionCount = nil
            saved.matching.maxSelectionCount = nil
        } else {
            saved.matching.minSelectionCount = parseCount(minSelText)
            saved.matching.maxSelectionCount = parseCount(maxSelText)
        }
        saved.placement = placementChoice == 1 ? .submenu : .topLevel
        switch variantChoice {
        case 1:
            saved.variants = .fixed(variantsFixed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        case 2:
            saved.variants = .directoryListing(variantsDir)
        default:
            saved.variants = nil
        }
        action = saved
        onSave(saved)
    }

    // 试运行:用与真实执行完全相同的环境契约跑脚本,但捕获 stdout/stderr/退出码内联展示。
    // 选真实目标(容器动作选文件夹,其余可多选文件);有变体则取当前第一个变体值。
    private func testRun() {
        guard !testRunning else { return }
        flushCommit()
        guard case .runScript(let spec) = action.kind else { return }
        // 空脚本:直接给清晰提示,别让用户选完目标才看到 exit 127 / 静默 exit 0。
        let empty = (kindChoice == 0 && scriptPath.trimmingCharacters(in: .whitespaces).isEmpty)
                 || (kindChoice == 1 && inlineSource.trimmingCharacters(in: .whitespaces).isEmpty)
        if empty {
            testRunResult = TestRunOutcome(
                result: ShellResult(exitCode: -1, stdout: "",
                                    stderr: String(localized: "editor.testRunNoScript"), timedOut: false),
                variant: nil, count: 0)
            return
        }
        let panel = NSOpenPanel()
        // 只让选这个动作真正会匹配的目标类型(any/files 选文件;any/folders/container 选文件夹)。
        panel.canChooseFiles = targetChoice == 0 || targetChoice == 1
        panel.canChooseDirectories = targetChoice != 1
        panel.allowsMultipleSelection = targetChoice != 3
        panel.message = String(localized: "editor.testRunPick")
        panel.prompt = String(localized: "editor.testRun")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let paths = urls.map(\.path)
        let variant = currentTestVariant()
        let env = ActionRunner.contractEnv()
        let cwd = ActionRunner.workingDirectory(for: urls)
        let base = AppPaths.configDirectory()
        testRunning = true
        // @MainActor in:阻塞执行在 Task.detached 里跑(不卡 UI),@State 写回回到主线程。
        testTask = Task { @MainActor in
            let r = await Task.detached {
                ShellRunner.runScript(spec, paths: paths, variant: variant,
                                      scriptBase: base, cwd: cwd, extraEnv: env)
            }.value
            if Task.isCancelled { return }   // 面板关闭/切换动作时丢弃结果
            testRunning = false
            testRunResult = TestRunOutcome(result: r, variant: variant, count: urls.count)
        }
    }

    /// 试运行用的变体值:固定列表取第一个;目录列举解析后取第一个;无变体为 nil。
    private func currentTestVariant() -> String? {
        switch variantChoice {
        case 1:
            return variantsFixed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        case 2:
            let raw = variantsDir.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            let dir = raw.hasPrefix("/") ? URL(fileURLWithPath: raw)
                                         : AppPaths.configDirectory().appendingPathComponent(raw)
            return TemplateStore.list(in: dir).first
        default:
            return nil
        }
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { scriptPath = url.path; commit() }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url,
           let id = Bundle(url: url)?.bundleIdentifier { appBundleID = id; commit() }
    }

    private func openScriptInEditor() {
        if case .runScript(let spec) = action.kind,
           let path = spec.resolvedScriptPath(base: AppPaths.configDirectory()) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

// MARK: - PvPackPanel(扩展包动作详情,只读脚本)
//
// 两种用法:
//   - 静态预览:无参初始化,展示设计稿示例数据(供 Preview / 设计对照)。
//   - 真实数据:传入 MenuAction(packID != nil)+ onSave,菜单标题/位置可改并写回;
//     作用对象/UTI 锁定;脚本只读(从安装目录读取);「打开仓库主页」用 packRepo。
//
// 当传入 action 时使用其字段;否则落回设计稿示例占位。

struct PvPackPanel: View {
    // 真实数据(可选):传入则进入可编辑/写回模式。
    var action: MenuAction?
    var packName: String?
    var onSave: ((MenuAction) -> Void)?

    // 静态预览占位(仅在无 action 时使用)。
    var title: String = "上传到图床"
    var previewPackName: String = "dev-tools"
    var menuTitle: String = "上传到图床"
    var placement: String = "子菜单「MenuMate ▸」"
    var target: String = "仅文件"
    var uti: String = "public.image"
    var script: String = "#!/bin/zsh\n# upload-to-imagebed.zsh — 只读\n: ${IMGBED_TOKEN:?}\ncurl -fsS -F \"file=@$1\" $API | pbcopy"
    var repoURL: String?
    var isOn: Bool = true

    // 真实数据的本地编辑态。
    @State private var editTitle: String = ""
    @State private var placementChoice: Int = 0   // 0 顶层 / 1 子菜单
    @State private var loaded = false

    private var liveMode: Bool { action != nil }

    private var resolvedTitle: String {
        if let action { return action.title.isEmpty ? String(localized: "editor.untitledAction") : action.title }
        return title
    }
    private var resolvedPackName: String { packName ?? previewPackName }

    private var resolvedTarget: String {
        guard let action else { return target }
        switch action.matching.targets {
        case .files: return String(localized: "editor.targetFilesOnly")
        case .folders: return String(localized: "editor.targetFoldersOnly")
        case .any: return String(localized: "editor.targetFilesAndFolders")
        case .container: return String(localized: "editor.targetContainer")
        }
    }
    private var resolvedUTI: String {
        guard let action else { return uti }
        return action.matching.utis.isEmpty ? String(localized: "panel.utiUnrestricted") : action.matching.utis.joined(separator: ", ")
    }
    private var resolvedScript: String {
        guard let action else { return script }
        if case .runScript(let spec) = action.kind, let path = spec.scriptPath,
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        return String(localized: "panel.scriptReadFailed")
    }
    private var resolvedRepoURL: String? {
        if let action, let repo = action.packRepo {
            return repo.hasPrefix("http") ? repo : "https://github.com/\(repo)"
        }
        return repoURL
    }

    private func lockRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: 11) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(MMColor.label2)
                .frame(width: 70, alignment: .trailing)
            MMField(value: value, mono: mono, width: 150)
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(MMColor.label3)
        }
        .opacity(0.7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                AppIcon(action?.icon.symbolName ?? "arrow.up.circle", size: 36, hue: .teal)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(resolvedTitle).font(.system(size: 15.5, weight: .semibold))
                        Badge(resolvedPackName, tone: .accent)
                    }
                    Text(String(localized: "panel.fromPackSubtitle"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(MMColor.label2)
                }
                Spacer(minLength: 0)
                if liveMode {
                    MMSwitch(Binding(
                        get: { action?.isEnabled ?? false },
                        set: { setEnabled($0) }))
                } else {
                    MMSwitch(.constant(isOn))
                }
            }
            Banner(String(localized: "panel.packReadOnlyBanner"),
                   tone: .accent, systemImage: "info.circle.fill")
            VStack(alignment: .leading, spacing: 10) {
                PvField(String(localized: "editor.menuTitle")) {
                    if liveMode {
                        MMField($editTitle, placeholder: String(localized: "editor.menuTitle"), width: 200)
                            .onChange(of: editTitle) { _ in commit() }
                    } else {
                        MMField(value: menuTitle, width: 200)
                    }
                }
                PvField(String(localized: "editor.placement")) {
                    HStack(spacing: 8) {
                        if liveMode {
                            placementPopup
                        } else {
                            MMPopup(placement, width: 180)
                        }
                        Text(String(localized: "panel.editable")).font(.system(size: 10.5)).foregroundStyle(MMColor.green)
                    }
                }
                lockRow(String(localized: "panel.target"), resolvedTarget)
                lockRow(String(localized: "panel.restrictUTI"), resolvedUTI, mono: true)
            }
            CodeBlock(resolvedScript, lang: String(localized: "panel.langZshReadOnly"), maxHeight: 140)
            HStack(spacing: 8) {
                MMButton(String(localized: "panel.openRepoHome"), systemImage: "arrow.up.right.square", size: .sm) {
                    if let s = resolvedRepoURL, let url = URL(string: s) { NSWorkspace.shared.open(url) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear(perform: load)
    }

    private var placementPopup: some View {
        let labels = [String(localized: "editor.placeTopLevel"), String(localized: "editor.placeSubmenu")]
        return Menu {
            ForEach(labels.indices, id: \.self) { i in
                Button(labels[i]) { placementChoice = i; commit() }
            }
        } label: {
            MMPopup(labels[placementChoice], width: 180)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func load() {
        guard let action, !loaded else { return }
        editTitle = action.title
        placementChoice = action.placement == .submenu ? 1 : 0
        loaded = true
    }

    private func commit() {
        guard loaded, var saved = action else { return }
        saved.title = editTitle
        saved.placement = placementChoice == 1 ? .submenu : .topLevel
        onSave?(saved)
    }

    private func setEnabled(_ value: Bool) {
        guard var saved = action else { return }
        saved.isEnabled = value
        onSave?(saved)
    }
}

// MARK: - PvSystemPanel(系统服务详情,仅可隐藏)

struct PvSystemPanel: View {
    let service: ManagedService
    /// 真实开关绑定(同左栏 serviceRow,经 servicesManager.setEnabled 写回)。
    @Binding var isOn: Bool
    var toggleEnabled: Bool = true

    var body: some View {
        PanelCard(
            iconSymbol: "square.grid.2x2",
            title: service.item.menuTitle,
            badge: (String(localized: "panel.systemService"), .orange),
            control: .hide,
            bundle: service.item.bundleID ?? String(localized: "panel.workflow"),
            locked: false,
            note: String(localized: "panel.systemServiceNote"),
            extra: service.isShortcutBased
                ? AnyView(Banner(String(localized: "panel.shortcutsHideOnlyBanner"), tone: .orange, systemImage: "info.circle.fill"))
                : nil,
            isOn: $isOn,
            toggleEnabled: toggleEnabled
        )
    }
}

// MARK: - PvOpaquePanel(第三方扩展详情,不可预览)

struct PvOpaquePanel: View {
    let ext: ManagedExtension
    /// 真实开关绑定(同左栏 extensionRow,经 extensionManager.setEnabled 写回)。
    @Binding var isOn: Bool
    var toggleEnabled: Bool = true

    var body: some View {
        PanelCard(
            iconSymbol: "square.stack",
            title: ext.displayName,
            badge: (String(localized: "panel.thirdPartyExtension"), .gray),
            control: .opaque,
            bundle: ext.info.bundleID,
            locked: ext.stuck,
            note: String(format: String(localized: "panel.opaqueNote"), ext.displayName),
            extra: ext.stuck
                ? AnyView(Banner(String(localized: "panel.extensionStuckBanner"), tone: .orange))
                : nil,
            isOn: $isOn,
            toggleEnabled: toggleEnabled
        )
    }
}

// MARK: - PanelCard(PvSystem / PvOpaque 共享外壳)

struct PanelCard: View {
    let iconSymbol: String
    let title: String
    let badge: (String, BadgeTone)
    let control: ControlDegree
    let bundle: String
    var locked: Bool = false
    let note: String
    var extra: AnyView?
    /// 头部开关接真实后端状态(与左栏预览行控制同一开关)。
    @Binding var isOn: Bool
    /// 开关是否可操作(能力探测失败 / busy / stuck 时禁用)。
    var toggleEnabled: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MMColor.label4, lineWidth: 1)
                    Image(systemName: iconSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(MMColor.label2)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(MMColor.label2)
                        }
                        Badge(badge.0, tone: badge.1)
                    }
                    Text(bundle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MMColor.label3)
                }
                Spacer(minLength: 0)
                MMSwitch($isOn)
                    .disabled(!toggleEnabled)
            }

            // 可控程度灰条
            HStack(spacing: 7) {
                ControlDot(control)
                Text(control == .hide ? String(localized: "panel.controlHideOnly") : String(localized: "panel.controlToggleOnly"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MMColor.label2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.content)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: kHairline))

            Text(note)
                .font(.system(size: 12.5))
                .foregroundStyle(MMColor.label2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let extra { extra }

            MMButton(String(localized: "panel.manageInSystemSettings"), systemImage: "arrow.up.right.square", size: .sm) {
                ExtensionManager.openSystemSettings()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - 文件类型分类 chips(限定 UTI 的友好叠加层)
//
// 引擎层早已支持按类型过滤(MatchRule.utis + UTType 一致性,见 image-convert 预设);
// 这里只把常见类型暴露成可点选 chips,底层仍写入 matching.utis:[String]——零 Core 改动。
// chips 与下方自定义 UTI 文本框双向同步(共享同一份逗号串);长尾/任意 UTI 仍可手填,
// 不被 chips 清除(toggle 只增删该分类对应的那一个 UTI)。

/// 友好分类 → 规范 UTI(UTType 一致性会命中其所有具体子类型)。
private let kTypeCategories: [(name: String, uti: String)] = [
    (String(localized: "panel.typeImage"), "public.image"),
    (String(localized: "panel.typeVideo"), "public.movie"),
    (String(localized: "panel.typeAudio"), "public.audio"),
    (String(localized: "panel.typePDF"), "com.adobe.pdf"),
    (String(localized: "panel.typeText"), "public.text"),
    (String(localized: "panel.typeSourceCode"), "public.source-code"),
    (String(localized: "panel.typeArchive"), "public.archive"),
    (String(localized: "panel.typeApplication"), "com.apple.application"),
]

struct TypeCategoryChips: View {
    @Binding var utisText: String

    private var current: [String] {
        utisText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(kTypeCategories, id: \.uti) { cat in
                let on = current.contains(cat.uti)
                TypeChip(title: cat.name, selected: on) { toggle(cat.uti, to: !on) }
            }
        }
        .frame(width: 240, alignment: .leading)
    }

    // 只改 utisText;持久化(commit)由下方 MMField 的 onChange(of: utisText) 统一触发。
    private func toggle(_ uti: String, to on: Bool) {
        var list = current
        if on { if !list.contains(uti) { list.append(uti) } }
        else { list.removeAll { $0 == uti } }
        utisText = list.joined(separator: ", ")
    }
}

private struct TypeChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? MMColor.accent : MMColor.label2)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(selected ? MMColor.accentTint : MMColor.control))
                .overlay(Capsule().stroke(selected ? MMColor.accent.opacity(0.5) : MMColor.hairline,
                                          lineWidth: kHairline))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 试运行结果

struct TestRunOutcome: Identifiable {
    let id = UUID()
    let result: ShellResult
    let variant: String?
    let count: Int
}

/// 试运行结果 sheet:退出码 + 变体 + stdout/stderr 内联(可选中复制)。
private struct TestRunSheet: View {
    let outcome: TestRunOutcome
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let r = outcome.result
        let ok = !r.timedOut && r.exitCode == 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(ok ? MMColor.green : MMColor.red)
                Text(String(localized: "editor.testRunTitle")).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
                Text(r.timedOut
                     ? String(localized: "editor.testRunTimedOut")
                     : String(format: String(localized: ok ? "editor.testRunSuccess" : "editor.testRunFailed"), Int(r.exitCode)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ok ? MMColor.green : MMColor.red)
            }
            if let v = outcome.variant {
                Text("\(String(localized: "editor.testRunVariant")): \(v)")
                    .font(.system(size: 11.5)).foregroundStyle(MMColor.label2)
            }
            outputBlock(String(localized: "editor.testRunStdout"), r.stdout)
            if !r.stderr.isEmpty { outputBlock(String(localized: "editor.testRunStderr"), r.stderr) }
            HStack {
                Spacer(minLength: 0)
                MMButton(String(localized: "editor.testRunClose"), kind: .primary, size: .sm) { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 470, height: 380)
    }

    @ViewBuilder private func outputBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(MMColor.label3)
            ScrollView {
                Text(text.isEmpty ? String(localized: "editor.testRunNoOutput") : text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(MMColor.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(MMColor.field)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MMColor.border, lineWidth: kHairline))
        }
    }
}
