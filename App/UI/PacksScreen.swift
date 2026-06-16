// PacksScreen.swift — 「扩展包」Tab(方案 A 行展开列表 + 空态)
//
// 精确复刻 docs/design/hifi/screen-packs.jsx:
//   ScreenPacks       顶部操作条 + 分组列表卡(每包一行 PackRow,可展开)/ 空态
//   PacksHeader       导入 / 浏览社区包 / topic 灰字 / 全部检查更新
//   PackRow           展开 chevron + AppIcon + 包名 + 有更新蓝点/徽章 + 仓库·SHA + n/m 已启用
//   ScreenPacksEmpty  居中插画空态
//
// 接 PackManager 真实数据:packs / setActionEnabled / uninstall / checkUpdate
// / cloneUpdate(经 PackUpdateSheet)/ confirmImport(经 PackImportSheet)。

import SwiftUI
import AppKit
import MenuMateCore

// MARK: - ScreenPacks(扩展包 Tab 主屏)

struct ScreenPacks: View {
    @ObservedObject var packManager: PackManager
    @ObservedObject private var state = AppState.shared

    @State private var expanded: Set<String> = []
    /// checkUpdate 结果缓存:key → 远端可用更新。
    @State private var updates: [String: PackUpdateAvailable] = [:]
    @State private var lastChecked: Date?
    @State private var checking = false

    // Sheet 路由
    @State private var showImport = false
    @State private var showDiscover = false
    @State private var pendingImport: RepoToImport?
    @State private var updatingPack: InstalledPack?
    @State private var scriptViewer: ScriptViewerTarget?

    var body: some View {
        Group {
            if packManager.packs.isEmpty {
                ScreenPacksEmpty(onImport: { showImport = true },
                                 onBrowse: browse)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MMColor.content)
        .onAppear { packManager.reload() }
        .sheet(isPresented: $showImport) {
            PackImportSheet(packManager: packManager) { showImport = false }
        }
        .sheet(item: $updatingPack) { pack in
            PackUpdateSheet(packManager: packManager, pack: pack) {
                updates[pack.key] = nil
                updatingPack = nil
            }
        }
        .sheet(item: $scriptViewer) { target in
            ScriptViewerSheet(title: target.title, path: target.path, code: target.code) {
                scriptViewer = nil
            }
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverPacksSheet(
                installedRepos: Set(packManager.packs.map { $0.repo.lowercased() }),
                onImport: { repo in
                    showDiscover = false
                    // 顺序呈现两个 sheet:先关发现,再开导入(预填仓库,仍走完整审查)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        pendingImport = RepoToImport(repo: repo)
                    }
                },
                onClose: { showDiscover = false })
        }
        .sheet(item: $pendingImport) { item in
            PackImportSheet(packManager: packManager, initialRepo: item.repo) {
                pendingImport = nil
                packManager.reload()
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            PacksHeader(onImport: { showImport = true },
                        onBrowse: browse,
                        checking: checking,
                        onCheckAll: checkAll)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(packManager.packs.enumerated()), id: \.element.id) { i, pack in
                            if i > 0 { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
                            PackRow(
                                pack: pack,
                                update: updates[pack.key],
                                expanded: expanded.contains(pack.key),
                                onToggleExpand: { toggleExpand(pack.key) },
                                onSetEnabled: { enabled, actionID in
                                    packManager.setActionEnabled(enabled, actionID: actionID)
                                },
                                onViewScript: { viewScript(pack: pack, action: $0) },
                                onUpdate: { updatingPack = pack },
                                onOpenRepo: { openRepo(pack) },
                                onUninstall: { uninstall(pack) }
                            )
                        }
                    }
                    .background(MMColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MMColor.hairline, lineWidth: 0.5))

                    Text(footerText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(MMColor.label3)
                        .padding(.horizontal, 4)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private var footerText: String {
        let checked: String
        if let lastChecked {
            let f = DateFormatter()
            f.dateFormat = String(localized: "packs.lastCheckedFormatToday")
            if !Calendar.current.isDateInToday(lastChecked) {
                f.dateFormat = String(localized: "packs.lastCheckedFormatOther")
            }
            checked = f.string(from: lastChecked)
        } else {
            checked = String(localized: "packs.lastCheckedNever")
        }
        return String(format: String(localized: "packs.footerLastChecked"), checked)
    }

    // MARK: 行为

    private func toggleExpand(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    private func browse() {
        showDiscover = true   // App 内发现社区包(扫描 menumate-pack topic),不再跳浏览器
    }

    private func openRepo(_ pack: InstalledPack) {
        // 优先用包记录的 repoURL;退化成 owner/repo 主页。
        let webURL: String
        if pack.repoURL.hasPrefix("http") {
            webURL = pack.repoURL.hasSuffix(".git") ? String(pack.repoURL.dropLast(4)) : pack.repoURL
        } else {
            webURL = "https://github.com/\(pack.repo)"
        }
        if let url = URL(string: webURL) { NSWorkspace.shared.open(url) }
    }

    private func uninstall(_ pack: InstalledPack) {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "packs.uninstallConfirmTitle"), pack.manifest.name)
        alert.informativeText = String(format: String(localized: "packs.uninstallConfirmBody"), pack.totalCount)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "packs.uninstall"))
        alert.addButton(withTitle: String(localized: "packs.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            try? packManager.uninstall(pack.key)
            expanded.remove(pack.key)
            updates[pack.key] = nil
        }
    }

    private func checkAll() {
        guard !checking else { return }
        checking = true
        Task {
            var found: [String: PackUpdateAvailable] = [:]
            for pack in packManager.packs {
                if let upd = await packManager.checkUpdate(pack.key) {
                    found[pack.key] = upd
                }
            }
            updates = found
            lastChecked = Date()
            checking = false
        }
    }

    private func viewScript(pack: InstalledPack, action: MenuAction) {
        guard case .runScript(let spec) = action.kind,
              let path = spec.scriptPath else { return }
        let code = (try? String(contentsOfFile: path, encoding: .utf8))
            ?? String(format: String(localized: "packs.scriptReadError"), path)
        // 显示相对仓库根的路径(去掉 packDir 前缀)更友好。
        let display = relativeScript(of: action, pack: pack) ?? path
        scriptViewer = ScriptViewerTarget(title: action.title, path: display, code: code)
    }

    private func relativeScript(of action: MenuAction, pack: InstalledPack) -> String? {
        // manifest 里 PackAction.script 即相对路径;按确定性 UUID 反查。
        for pa in pack.manifest.actions
        where PackManager.actionUUID(packKey: pack.key, packActionID: pa.id) == action.id {
            return pa.script
        }
        return nil
    }
}

struct ScriptViewerTarget: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let code: String
}

struct RepoToImport: Identifiable {
    let id = UUID()
    let repo: String
}

// MARK: - PacksHeader(顶部操作条)

struct PacksHeader: View {
    let onImport: () -> Void
    let onBrowse: () -> Void
    var checking: Bool = false
    let onCheckAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MMButton(String(localized: "packs.importPack"), systemImage: "plus", kind: .primary, action: onImport)
            MMButton(String(localized: "packs.browseCommunity"), systemImage: "magnifyingglass", kind: .plain, action: onBrowse)
            Text("topic: menumate-pack")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MMColor.label3)
            Spacer(minLength: 0)
            if checking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "packs.checking")).font(.system(size: 12)).foregroundStyle(MMColor.label2)
                }
            } else {
                MMButton(String(localized: "packs.checkAllUpdates"), systemImage: "arrow.clockwise", size: .sm, action: onCheckAll)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - PackRow(单包行 + 展开详情)

struct PackRow: View {
    let pack: InstalledPack
    var update: PackUpdateAvailable?
    let expanded: Bool
    let onToggleExpand: () -> Void
    let onSetEnabled: (Bool, UUID) -> Void
    let onViewScript: (MenuAction) -> Void
    let onUpdate: () -> Void
    let onOpenRepo: () -> Void
    let onUninstall: () -> Void

    @ObservedObject private var state = AppState.shared

    /// 该包的动作(按 sortOrder 稳定排序),用于展开列表 + 启停。
    private var actions: [MenuAction] {
        state.config.actions
            .filter { $0.packID == pack.key }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded { expandedBody }
        }
    }

    private var header: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 10) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MMColor.label3)
                    .frame(width: 12)
                AppIcon(pack.manifest.icon, size: 30, hue: .teal)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(pack.manifest.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(MMColor.label)
                        if update != nil {
                            MMDot()
                            Badge(String(localized: "packs.updateAvailable"), tone: .accent)
                        }
                    }
                    Text("\(pack.repo) · \(pack.commitSHA)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MMColor.label2)
                }
                Spacer(minLength: 0)
                Text(String(format: String(localized: "packs.enabledCount"), pack.enabledCount, pack.totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.label2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 动作小列表
            VStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { i, action in
                    if i > 0 { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
                    HStack(spacing: 9) {
                        MMSwitch(
                            Binding(get: { action.isEnabled },
                                    set: { onSetEnabled($0, action.id) }),
                            scale: 0.62)
                        Text(action.title)
                            .font(.system(size: 12.5))
                            .foregroundStyle(MMColor.label)
                        Spacer(minLength: 0)
                        MMButton(String(localized: "packs.viewScript"), kind: .plain, size: .sm) { onViewScript(action) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .opacity(action.isEnabled ? 1 : 0.55)
                }
            }
            .background(MMColor.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.5))

            // 按钮行
            HStack(spacing: 8) {
                if update != nil {
                    MMButton(String(localized: "packs.updateEllipsis"), systemImage: "arrow.down.circle",
                             kind: .primary, size: .sm, action: onUpdate)
                }
                MMButton(String(localized: "packs.openRepoHome"), systemImage: "arrow.up.right.square",
                         size: .sm, action: onOpenRepo)
                Spacer(minLength: 0)
                MMButton(String(localized: "packs.uninstallEllipsis"), systemImage: "trash", kind: .danger, size: .sm, action: onUninstall)
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 14)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .background(MMColor.content)
        .overlay(alignment: .top) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
        }
    }
}

// MARK: - ScreenPacksEmpty(空态)

struct ScreenPacksEmpty: View {
    let onImport: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(MMColor.accentTint)
                    .frame(width: 96, height: 96)
                Image(systemName: "shippingbox")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(MMColor.accent)
            }
            VStack(spacing: 6) {
                Text(String(localized: "packs.emptyTitle"))
                    .font(.system(size: 17, weight: .semibold))
                Text(String(localized: "packs.emptyBody"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(MMColor.label2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .frame(maxWidth: 360)
            }
            HStack(spacing: 10) {
                MMButton(String(localized: "packs.importPack"), systemImage: "plus", kind: .primary, action: onImport)
                MMButton(String(localized: "packs.browseCommunity"), systemImage: "magnifyingglass", action: onBrowse)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
