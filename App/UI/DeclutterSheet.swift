import SwiftUI
import MenuMateCore

// 「一键整理」审查 sheet:列出别的来源塞进右键菜单的项(系统服务 + 第三方 Finder 扩展),
// 第三方项预勾,确认后批量隐藏(走现有 setEnabled),记录精确改动集合供会话级撤销。
// 绝不列、不动 MenuMate 自己的动作;MenuMate 自己的扩展(com.menumate.*)也被 isThirdParty 排除。
struct DeclutterSheet: View {
    @ObservedObject var servicesManager: ServicesManager
    @ObservedObject var extensionManager: ExtensionManager
    let onClose: () -> Void

    @State private var selectedServices: Set<String> = []   // ManagedService.id
    @State private var selectedExts: Set<String> = []       // bundleID
    @State private var loaded = false
    @State private var applied = false
    @State private var lastServices: [ManagedService] = []
    @State private var lastExts: [ManagedExtension] = []

    // 只整理「当前还显示/启用」的项(隐藏已隐藏的没意义)。
    private func isTP(_ s: ManagedService) -> Bool { Declutter.isThirdParty(bundleID: s.item.bundleID, bundlePath: s.item.bundlePath) }
    private func isTP(_ e: ManagedExtension) -> Bool { Declutter.isThirdParty(bundleID: e.info.bundleID, bundlePath: e.info.path) }
    private var thirdPartyServices: [ManagedService] { servicesManager.services.filter { $0.enabledInContextMenu && isTP($0) } }
    private var systemServices: [ManagedService] { servicesManager.services.filter { $0.enabledInContextMenu && !isTP($0) } }
    private var thirdPartyExts: [ManagedExtension] { extensionManager.extensions.filter { $0.info.election == .use && isTP($0) } }

    private var selectedCount: Int {
        let shownSvc = Set(thirdPartyServices.map(\.id)).union(systemServices.map(\.id))
        return selectedServices.intersection(shownSvc).count + selectedExts.intersection(Set(thirdPartyExts.map(\.id))).count
    }

    // 应用后:扩展可能被宿主抢回(stuck,election 仍是 .use)→ 不算成功。响应式从实况重算,
    // 不把乐观快照当成功数(评审 DECL-1/2)。
    private var rejectedExts: [ManagedExtension] {
        lastExts.filter { rec in extensionManager.extensions.contains { $0.id == rec.id && $0.info.election == .use } }
    }
    private var hiddenCount: Int { max(0, lastServices.count + lastExts.count - rejectedExts.count) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                AppIcon("wand.and.sparkles", size: 34, hue: .teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "declutter.title")).font(.system(size: 14.5, weight: .semibold))
                    Text(String(localized: "declutter.subtitle")).font(.system(size: 11.5)).foregroundStyle(MMColor.label2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 16)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                MMButton(String(localized: "declutter.selectAll"), size: .sm) { selectAll() }
                MMButton(String(localized: "declutter.selectNone"), size: .sm) { selectedServices = []; selectedExts = [] }
            }
            .padding(.horizontal, 20).padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !thirdPartyServices.isEmpty {
                        group(String(format: String(localized: "declutter.groupThirdPartyServices"), thirdPartyServices.count),
                              recommended: true) {
                            ForEach(thirdPartyServices) { s in serviceRow(s) }
                        }
                    }
                    if !thirdPartyExts.isEmpty {
                        group(String(format: String(localized: "declutter.groupThirdPartyExtensions"), thirdPartyExts.count),
                              recommended: true) {
                            ForEach(thirdPartyExts) { e in extRow(e) }
                        }
                    }
                    if !systemServices.isEmpty {
                        group(String(format: String(localized: "declutter.groupSystem"), systemServices.count),
                              recommended: false) {
                            ForEach(systemServices) { s in serviceRow(s) }
                        }
                    }
                    if thirdPartyServices.isEmpty && thirdPartyExts.isEmpty && systemServices.isEmpty {
                        Text(String(localized: "declutter.empty")).font(.system(size: 12)).foregroundStyle(MMColor.label3)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }

            footer
        }
        .frame(width: 540, height: 560)
        .onAppear {
            guard !loaded else { return }
            selectedServices = Set(thirdPartyServices.map(\.id))
            selectedExts = Set(thirdPartyExts.map(\.id))
            loaded = true
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
            HStack(spacing: 10) {
                if applied {
                    Image(systemName: rejectedExts.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(rejectedExts.isEmpty ? MMColor.green : MMColor.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(format: String(localized: "declutter.result"), hiddenCount))
                            .font(.system(size: 12))
                        if !rejectedExts.isEmpty {
                            Text(String(format: String(localized: "declutter.rejectedCount"), rejectedExts.count))
                                .font(.system(size: 10)).foregroundStyle(MMColor.red)
                        } else if let err = servicesManager.lastError {
                            Text(err).font(.system(size: 10)).foregroundStyle(MMColor.red).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                    if !lastServices.isEmpty || !lastExts.isEmpty {
                        MMButton(String(localized: "declutter.undo"), size: .sm) { undo() }
                    }
                    MMButton(String(localized: "declutter.done"), kind: .primary, size: .sm) { onClose() }
                } else {
                    Text(String(localized: "declutter.applyHint")).font(.system(size: 11)).foregroundStyle(MMColor.label3)
                    Spacer(minLength: 0)
                    MMButton(String(localized: "declutter.cancel"), size: .sm) { onClose() }
                    MMButton(String(format: String(localized: "declutter.apply"), selectedCount), kind: .primary, size: .sm) { apply() }
                        .disabled(selectedCount == 0)
                        .opacity(selectedCount == 0 ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    @ViewBuilder private func group<Content: View>(_ title: String, recommended: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MMColor.label2)
                if recommended { Badge(String(localized: "declutter.recommendedHidden"), tone: .orange) }
            }
            VStack(spacing: 0) { content() }
                .background(MMColor.card)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MMColor.hairline, lineWidth: 0.5))
        }
    }

    @ViewBuilder private func serviceRow(_ s: ManagedService) -> some View {
        row(checked: bind($selectedServices, s.id),
            name: s.item.localizedTitle?.isEmpty == false ? s.item.localizedTitle! : s.item.menuTitle,
            subtitle: s.item.bundleID ?? s.item.bundlePath ?? "",
            shortcutsOnly: s.isShortcutBased, stuck: false)
    }

    @ViewBuilder private func extRow(_ e: ManagedExtension) -> some View {
        row(checked: bind($selectedExts, e.id),
            name: e.displayName, subtitle: e.info.bundleID, shortcutsOnly: false, stuck: e.stuck)
    }

    @ViewBuilder private func row(checked: Binding<Bool>, name: String, subtitle: String, shortcutsOnly: Bool, stuck: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: checked).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12)).foregroundStyle(MMColor.label).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(MMColor.label3).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if shortcutsOnly { Badge(String(localized: "declutter.shortcutsOnlyHide"), tone: .gray) }
            if stuck { Badge(String(localized: "declutter.rejected"), tone: .red) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func bind(_ set: Binding<Set<String>>, _ id: String) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(id) },
                set: { if $0 { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } })
    }

    private func selectAll() {
        selectedServices = Set(thirdPartyServices.map(\.id)).union(systemServices.map(\.id))
        selectedExts = Set(thirdPartyExts.map(\.id))
    }

    private func apply() {
        var changedSvc: [ManagedService] = []
        var changedExt: [ManagedExtension] = []
        for s in servicesManager.services where selectedServices.contains(s.id) && s.enabledInContextMenu {
            servicesManager.setEnabled(false, for: s); changedSvc.append(s)
        }
        for e in extensionManager.extensions where selectedExts.contains(e.id) && e.info.election == .use {
            extensionManager.setEnabled(false, for: e); changedExt.append(e)
        }
        lastServices = changedSvc
        lastExts = changedExt
        if !changedSvc.isEmpty || !changedExt.isEmpty { servicesManager.restartFinder() }
        applied = true
    }

    private func undo() {
        for s in lastServices { servicesManager.setEnabled(true, for: s) }
        for e in lastExts { extensionManager.setEnabled(true, for: e) }
        if !lastServices.isEmpty || !lastExts.isEmpty { servicesManager.restartFinder() }
        lastServices = []
        lastExts = []
        applied = false
    }
}
