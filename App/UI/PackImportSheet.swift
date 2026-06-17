// PackImportSheet.swift — 扩展包导入审查流程 + 更新 diff
//
// 精确复刻 docs/design/hifi/screen-import.jsx:
//   PackImportSheet  ① 粘贴 URL+克隆 → ②C 左右分栏逐脚本审查 → ③ 确认导入
//   PackUpdateSheet  更新 diff(旧→新 SHA 徽章、橙横幅、逐文件 diff 行 +/−)
//
// 安全约束(对照 PackManager + HANDOFF):
//   - clone 阶段绝不执行脚本;仅展示只读源码。
//   - 审查页未全部查看时「继续」禁用。
//   - 导入后所有动作默认禁用。
//   - 任意阶段取消 → discard(tempDir:) 清理临时目录。

import SwiftUI
import AppKit
import MenuMateCore

// MARK: - SheetHead(对照 jsx SheetHead)

private struct SheetHead: View {
    var step: Int?
    let title: String
    var sub: String?
    var hue: AppIconHue = .teal
    var icon: String = "shippingbox"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppIcon(icon, size: 34, hue: hue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                if let sub {
                    Text(sub)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(MMColor.label2)
                }
            }
            Spacer(minLength: 0)
            if let step {
                Text(String(format: String(localized: "packImport.stepIndicator"), step))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MMColor.label2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(MMColor.control)
                    .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
        }
    }
}

// MARK: - SheetFooter(分隔线 + 右对齐按钮区)

private struct SheetFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
            HStack(spacing: 9) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - PackImportSheet(导入审查状态机)

struct PackImportSheet: View {
    @ObservedObject var packManager: PackManager
    /// 完成或取消后关闭(由父视图把绑定置 false)。
    let onClose: () -> Void

    /// initialRepo:从「发现社区包」点导入时预填仓库(用户仍需走完整审查流程)。
    init(packManager: PackManager, initialRepo: String = "", onClose: @escaping () -> Void) {
        self._packManager = ObservedObject(wrappedValue: packManager)
        self.onClose = onClose
        self._urlText = State(initialValue: initialRepo)
    }

    enum Phase: Equatable {
        case url
        case cloning
        case review
        case confirm
        case done
        case error(String)
    }

    @State private var phase: Phase = .url
    @State private var urlText: String = ""
    @State private var cloned: ClonedPack?
    /// 已查看的动作 id 集合(PackAction.id)。
    @State private var viewed: Set<String> = []
    @State private var selectedActionID: String?
    /// 已确认知悉「未声明文件」(仅当包内存在这类文件时作为额外放行条件)。
    @State private var extrasAck = false

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .url, .cloning: step1
            case .review:        step2
            case .confirm:       step3
            case .done:          step3   // 过渡态;onClose 已被触发
            case .error(let m):  errorView(m)
            }
        }
        .frame(width: sheetWidth, height: 500)
        .background(MMColor.content)
    }

    private var sheetWidth: CGFloat {
        switch phase {
        case .review: return 720
        default:      return 470
        }
    }

    // MARK: ① 粘贴 URL + 克隆

    @ViewBuilder private var step1: some View {
        let isCloning = phase == .cloning
        VStack(spacing: 0) {
            SheetHead(step: 1, title: String(localized: "packImport.step1Title"))
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "packImport.urlPrompt"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(MMColor.label2)
                MMField($urlText, placeholder: "lihua/menumate-dev-tools", mono: true)
                    .frame(maxWidth: .infinity)
                    .disabled(isCloning)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(MMColor.label3)
                    Text(String(localized: "packImport.urlHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(MMColor.label3)
                }
                if isCloning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(String(localized: "packImport.cloning")).font(.system(size: 12))
                            }
                            Spacer()
                        }
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    .padding(12)
                    .background(MMColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MMColor.hairline, lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            Spacer(minLength: 0)
            SheetFooter {
                MMButton(String(localized: "packImport.cancel")) { cancel() }
                Spacer(minLength: 0)
                if isCloning {
                    MMButton(String(localized: "packImport.cloningButton"), kind: .primary).disabled(true).opacity(0.5)
                } else {
                    MMButton(String(localized: "packImport.next"), kind: .primary) { startClone() }
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
            }
        }
    }

    // MARK: ②C 左右分栏审查

    @ViewBuilder private var step2: some View {
        if let cloned {
            let actions = cloned.manifest.actions
            let sel = actions.first(where: { $0.id == selectedActionID }) ?? actions.first
            VStack(spacing: 0) {
                SheetHead(step: 2, title: String(format: String(localized: "packImport.reviewTitle"), cloned.manifest.name),
                          sub: "\(cloned.repo) · \(cloned.commitSHA)")
                VStack(spacing: 0) {
                    Banner(String(localized: "packImport.reviewWarning"),
                           tone: .red)
                        .padding(.horizontal, 20)
                        .padding(.top, 11)

                    if !cloned.extraFiles.isEmpty {
                        undeclaredFilesSection(cloned.extraFiles)
                            .padding(.horizontal, 20)
                            .padding(.top, 9)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        reviewList(actions: actions)
                            .frame(width: 200)
                        reviewDetail(sel: sel)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity)
                }
                SheetFooter {
                    Text(String(format: String(localized: "packImport.actionsScriptsCount"), actions.count, cloned.scripts.count))
                        .font(.system(size: 11.5))
                        .foregroundStyle(MMColor.label3)
                    Spacer(minLength: 0)
                    MMButton(String(localized: "packImport.back")) { phase = .url }
                    MMButton(String(localized: "packImport.continue"), kind: .primary) { phase = .confirm }
                        .disabled(!canContinue(actions))
                        .opacity(canContinue(actions) ? 1 : 0.4)
                }
            }
        }
    }

    private func reviewList(actions: [PackAction]) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                    let isSel = (selectedActionID ?? actions.first?.id) == a.id
                    HStack(spacing: 8) {
                        if viewed.contains(a.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(isSel ? Color.white : MMColor.green)
                        } else {
                            Circle()
                                .strokeBorder(isSel ? Color.white.opacity(0.6) : MMColor.label4,
                                              lineWidth: 1.3)
                                .frame(width: 14, height: 14)
                        }
                        Text(a.title)
                            .font(.system(size: 12, weight: isSel ? .semibold : .regular))
                            .foregroundStyle(isSel ? Color.white : MMColor.label)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isSel ? MMColor.accent : Color.clear)
                    .overlay(alignment: .top) {
                        if i > 0 { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedActionID = a.id
                        viewed.insert(a.id)
                    }
                }
            }
            .background(MMColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.5))

            Text(String(format: String(localized: "packImport.viewedProgress"), viewed.count, actions.count))
                .font(.system(size: 11))
                .foregroundStyle(MMColor.label3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    @ViewBuilder private func reviewDetail(sel: PackAction?) -> some View {
        if let sel, let cloned {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(sel.title).font(.system(size: 13, weight: .semibold))
                    Badge(matchSummary(sel), tone: .gray)
                    Spacer(minLength: 0)
                    Text(sel.script)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MMColor.label3)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                CodeBlock(cloned.scripts[sel.id] ?? String(localized: "packImport.scriptReadFailed"),
                          lang: String(localized: "packImport.scriptReadonlyLang"))
                    .frame(maxHeight: .infinity)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: ③ 确认

    @ViewBuilder private var step3: some View {
        if let cloned {
            VStack(spacing: 0) {
                SheetHead(step: 3, title: String(localized: "packImport.confirmTitle"))
                VStack(spacing: 14) {
                    AppIcon(cloned.manifest.icon, size: 52, hue: .teal)
                    VStack(spacing: 2) {
                        Text(cloned.manifest.name).font(.system(size: 15, weight: .semibold))
                        Text(String(format: String(localized: "packImport.actionsCommit"), cloned.manifest.actions.count, cloned.commitSHA))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(MMColor.label2)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(MMColor.accent)
                        Text(String(localized: "packImport.confirmDisabledNote"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(MMColor.label)
                            .lineSpacing(1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(MMColor.accentTint)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                Spacer(minLength: 0)
                SheetFooter {
                    MMButton(String(localized: "packImport.back")) { phase = .review }
                    Spacer(minLength: 0)
                    MMButton(String(localized: "packImport.import"), systemImage: "arrow.down.circle", kind: .primary) {
                        doImport(cloned)
                    }
                }
            }
        }
    }

    // MARK: error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 0) {
            SheetHead(title: String(localized: "packImport.errorTitle"), hue: .red, icon: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 12) {
                Banner(message, tone: .red)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            Spacer(minLength: 0)
            SheetFooter {
                MMButton(String(localized: "packImport.cancel")) { cancel() }
                Spacer(minLength: 0)
                MMButton(String(localized: "packImport.retry"), kind: .primary) { phase = .url }
            }
        }
    }

    // MARK: 逻辑

    private func allViewed(_ actions: [PackAction]) -> Bool {
        !actions.isEmpty && actions.allSatisfy { viewed.contains($0.id) }
    }

    /// 放行条件:看完每个声明脚本 + (若有未声明文件)勾选已审查。
    private func canContinue(_ actions: [PackAction]) -> Bool {
        guard allViewed(actions) else { return false }
        return (cloned?.extraFiles.isEmpty ?? true) || extrasAck
    }

    /// 暴露 manifest 之外的文件,逼审查者正视隐藏脚本/可执行/二进制。
    @ViewBuilder private func undeclaredFilesSection(_ files: [PackFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: String(localized: "packImport.undeclaredTitle"), files.count))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MMColor.red)
            ForEach(files, id: \.relativePath) { f in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11)).foregroundStyle(MMColor.label3)
                    Text(f.relativePath)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(MMColor.label)
                        .lineLimit(1).truncationMode(.middle)
                    if f.isExecutable { Badge(String(localized: "packImport.flagExecutable"), tone: .red) }
                    if f.isBinary { Badge(String(localized: "packImport.flagBinary"), tone: .gray) }
                    Spacer(minLength: 0)
                }
            }
            Toggle(isOn: $extrasAck) {
                Text(String(localized: "packImport.undeclaredAck")).font(.system(size: 11.5))
            }
            .toggleStyle(.checkbox)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(MMColor.red.opacity(0.4), lineWidth: 0.8))
    }

    private func matchSummary(_ a: PackAction) -> String {
        let target: String
        switch a.targets {
        case .files: target = String(localized: "packImport.targetFilesOnly")
        case .folders: target = String(localized: "packImport.targetFoldersOnly")
        case .any: target = String(localized: "packImport.targetFilesAndFolders")
        case .container: target = String(localized: "packImport.targetContainer")
        }
        var parts = [target]
        if !a.utis.isEmpty { parts.append(a.utis.joined(separator: " · ")) }
        parts.append(a.placement == .submenu ? String(localized: "packImport.placementSubmenu") : String(localized: "packImport.placementTop"))
        return parts.joined(separator: " · ")
    }

    private func startClone() {
        let input = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        phase = .cloning
        Task {
            do {
                let result = try await packManager.clone(input)
                cloned = result
                // 不自动标记任何项为已看:进入审查页时 viewed 为空,
                // 首项仅作展示,用户必须主动点击每一项(含首项)才计入「已查看」。
                viewed = []
                selectedActionID = result.manifest.actions.first?.id
                phase = .review
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func doImport(_ cloned: ClonedPack) {
        do {
            try packManager.confirmImport(cloned)
            self.cloned = nil   // 已移动到位,无需 discard。
            phase = .done
            onClose()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func cancel() {
        if let cloned { packManager.discard(tempDir: cloned.tempDir) }
        cloned = nil
        onClose()
    }
}

// MARK: - PackUpdateSheet(更新 diff)

struct PackUpdateSheet: View {
    @ObservedObject var packManager: PackManager
    let pack: InstalledPack
    let onClose: () -> Void

    enum Phase: Equatable {
        case loading
        case ready
        case error(String)
    }

    @State private var phase: Phase = .loading
    @State private var update: PackUpdate?

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .loading: loadingView
            case .ready:   readyView
            case .error(let m): errorView(m)
            }
        }
        .frame(width: phase == .ready ? 720 : 470, height: 500)
        .background(MMColor.content)
        .onAppear(perform: load)
    }

    // MARK: loading

    private var loadingView: some View {
        VStack(spacing: 0) {
            updateHead
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(String(localized: "packImport.updateCloning"))
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.label2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer(primaryTitle: nil)
        }
    }

    // MARK: ready(diff 列表)

    @ViewBuilder private var readyView: some View {
        if let update {
            let changed = update.diffsByFile.filter { $0.isModified }
            let added = update.newAddedActions(currentManifest: pack.manifest)
            VStack(spacing: 0) {
                updateHead
                Banner(updateSummary(changed: changed.count, added: added.count),
                       tone: .orange)
                    .padding(.horizontal, 20)
                    .padding(.top, 11)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(update.diffsByFile.enumerated()), id: \.offset) { _, fd in
                            DiffFileCard(diff: fd)
                        }
                        ForEach(Array(added.enumerated()), id: \.offset) { _, pa in
                            addedActionRow(pa)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                footer(primaryTitle: String(localized: "packImport.applyUpdate"))
            }
        }
    }

    private func addedActionRow(_ pa: PackAction) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MMColor.green)
            Text(String(localized: "packImport.newActionPrefix"))
                .font(.system(size: 12))
            + Text(pa.script)
                .font(.system(size: 12, design: .monospaced))
            Badge(String(localized: "packImport.defaultDisabled"), tone: .gray)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MMColor.green.opacity(MMColor.isDark ? 0.16 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 0) {
            updateHead
            Banner(message, tone: .red)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Spacer(minLength: 0)
            footer(primaryTitle: nil)
        }
    }

    // MARK: head / footer

    private var updateHead: some View {
        HStack(alignment: .center, spacing: 12) {
            AppIcon(pack.manifest.icon, size: 34, hue: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "packImport.updateTitle"), pack.manifest.name))
                    .font(.system(size: 14.5, weight: .semibold))
                Text(String(localized: "packImport.updateHeadSub"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(MMColor.label2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Badge(pack.commitSHA, tone: .gray)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MMColor.label3)
                Badge(update?.newSHA ?? "…", tone: .accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
        }
    }

    private func footer(primaryTitle: String?) -> some View {
        SheetFooter {
            MMButton(String(localized: "packImport.cancel")) { cancel() }
            Spacer(minLength: 0)
            if let primaryTitle {
                MMButton(primaryTitle, systemImage: "arrow.down.circle", kind: .primary) {
                    apply()
                }
            }
        }
    }

    private func updateSummary(changed: Int, added: Int) -> String {
        var parts: [String] = []
        if changed > 0 { parts.append(String(format: String(localized: "packImport.scriptsChanged"), changed)) }
        if added > 0 { parts.append(String(format: String(localized: "packImport.newActionsCount"), added)) }
        if parts.isEmpty { parts.append(String(localized: "packImport.manifestUpdated")) }
        let head = parts.joined(separator: String(localized: "packImport.summarySeparator"))
        return added > 0
            ? String(format: String(localized: "packImport.updateSummaryWithDisabled"), head)
            : String(format: String(localized: "packImport.updateSummaryPlain"), head)
    }

    // MARK: 逻辑

    private func load() {
        Task {
            do {
                let result = try await packManager.cloneUpdate(pack.key)
                update = result
                phase = .ready
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func apply() {
        guard let update else { return }
        do {
            try packManager.applyUpdate(pack.key, update)
            self.update = nil   // tempDir 已移动到位。
            onClose()
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func cancel() {
        if let update { packManager.discard(tempDir: update.tempDir) }
        update = nil
        onClose()
    }
}

// 远端新增的脚本路径 → 对应 PackAction(用于「新增动作」行)。
private extension PackUpdate {
    func newAddedActions(currentManifest: PackManifest) -> [PackAction] {
        let oldPaths = Set(currentManifest.actions.map(\.script))
        return newManifest.actions.filter { !oldPaths.contains($0.script) }
    }
}

// MARK: - DiffFileCard(单文件 diff:文件名 + 增删统计 + 逐行红绿)

struct DiffFileCard: View {
    let diff: PackUpdate.FileDiff

    @State private var expanded: Bool

    init(diff: PackUpdate.FileDiff) {
        self.diff = diff
        // 有改动 / 新增的文件默认展开;未变更折叠。
        _expanded = State(initialValue: diff.isModified || diff.isAdded)
    }

    private var lines: [DiffLine] { DiffLine.compute(old: diff.oldText, new: diff.newText) }
    private var added: Int { lines.filter { $0.kind == .add }.count }
    private var removed: Int { lines.filter { $0.kind == .del }.count }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MMColor.label3)
                    Text(diff.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MMColor.label)
                    if diff.isAdded { Badge(String(localized: "packImport.diffAdded"), tone: .green) }
                    if diff.isRemoved { Badge(String(localized: "packImport.diffRemoved"), tone: .red) }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text("+\(added)")
                            .foregroundStyle(MMColor.green)
                        Text("−\(removed)")
                            .foregroundStyle(MMColor.red)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle().fill(MMColor.separator).frame(height: 0.5)
                VStack(spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        DiffRow(line: line)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(MMColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(MMColor.hairline, lineWidth: 0.5))
    }
}

// MARK: - DiffRow / DiffLine(行级红绿对照)

struct DiffLine: Identifiable {
    enum Kind { case ctx, add, del }
    let id = UUID()
    let kind: Kind
    let text: String

    /// 朴素行级 diff:公共前缀(未变更)→ 旧行全删 → 新行全增。
    /// FileDiff 给的是 old/new 全文,这里做最简单的「整块对照」:
    /// 公共前缀行原样显示,其后旧文剩余行标删、新文剩余行标增。
    static func compute(old: String?, new: String?) -> [DiffLine] {
        let oldLines = (old ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = (new ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // 纯新增 / 纯删除快速路径。
        if old == nil { return newLines.map { DiffLine(kind: .add, text: $0) } }
        if new == nil { return oldLines.map { DiffLine(kind: .del, text: $0) } }

        // 公共前缀。
        var prefix = 0
        while prefix < oldLines.count && prefix < newLines.count && oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        // 公共后缀(不与前缀重叠)。
        var suffix = 0
        while suffix < (oldLines.count - prefix) && suffix < (newLines.count - prefix)
                && oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        var result: [DiffLine] = []
        for i in 0..<prefix { result.append(DiffLine(kind: .ctx, text: oldLines[i])) }
        let oldMid = oldLines[prefix..<(oldLines.count - suffix)]
        let newMid = newLines[prefix..<(newLines.count - suffix)]
        for l in oldMid { result.append(DiffLine(kind: .del, text: l)) }
        for l in newMid { result.append(DiffLine(kind: .add, text: l)) }
        for i in (oldLines.count - suffix)..<oldLines.count { result.append(DiffLine(kind: .ctx, text: oldLines[i])) }
        return result
    }
}

struct DiffRow: View {
    let line: DiffLine

    private var bg: Color {
        switch line.kind {
        case .add: return MMColor.green.opacity(MMColor.isDark ? 0.18 : 0.12)
        case .del: return MMColor.red.opacity(MMColor.isDark ? 0.18 : 0.10)
        case .ctx: return .clear
        }
    }
    private var bar: Color {
        switch line.kind {
        case .add: return MMColor.green
        case .del: return MMColor.red
        case .ctx: return .clear
        }
    }
    private var sign: String {
        switch line.kind {
        case .add: return "+"
        case .del: return "−"
        case .ctx: return " "
        }
    }
    private var signColor: Color {
        switch line.kind {
        case .add: return MMColor.green
        case .del: return MMColor.red
        case .ctx: return MMColor.label3
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(bar).frame(width: 3)
            Text(sign)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(signColor)
                .frame(width: 18)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MMColor.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
        }
        .background(bg)
    }
}

// MARK: - ScriptViewerSheet(「查看脚本」只读弹窗)

struct ScriptViewerSheet: View {
    let title: String
    let path: String
    let code: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer(minLength: 0)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MMColor.label3)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MMColor.separator).frame(height: 0.5)
            }
            CodeBlock(code, lang: String(localized: "packImport.zshReadonlyLang"))
                .padding(16)
            SheetFooter {
                Spacer(minLength: 0)
                MMButton(String(localized: "packImport.close"), kind: .primary) { onClose() }
            }
        }
        .frame(width: 560, height: 460)
        .background(MMColor.content)
    }
}
