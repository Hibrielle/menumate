import SwiftUI
import AppKit

// 打开方式 Tab — 对照 docs/design/hifi/screen-system.jsx ScreenOpenWith。
// 说明段 + 扫描按钮 + 扫描中态 + 按 App 分组卡(DupGroup/DupRow)+ 不支持时 info 横幅。
struct OpenWithTab: View {
    @StateObject private var cleaner = OpenWithCleaner()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                // 顶部:说明文案(左,灰)+ 扫描按钮。
                HStack(alignment: .top, spacing: 12) {
                    Text(String(localized: "openWith.intro"))
                        .font(.system(size: 12))
                        .foregroundStyle(MMColor.label2)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MMButton(String(localized: "openWith.scan"), systemImage: "magnifyingglass", kind: .primary) {
                        cleaner.scan()
                    }
                    .disabled(cleaner.scanning)
                }

                // 扫描中态:转圈 + 文案。
                if cleaner.scanning {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text(String(localized: "openWith.scanning"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(MMColor.label2)
                    }
                }

                // 按 App 分组卡。
                ForEach(cleaner.groups) { group in
                    DupGroupView(group: group, cleaner: cleaner)
                }

                if !cleaner.scanning && cleaner.groups.isEmpty {
                    Text(String(localized: "openWith.emptyState"))
                        .font(.system(size: 12))
                        .foregroundStyle(MMColor.label3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }

                // 系统不支持逐项反注册时的 info 横幅。
                if !cleaner.unregisterSupported {
                    Banner(String(localized: "openWith.unsupportedBanner"),
                           tone: .info, systemImage: "info.circle")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(MMColor.content)
        .onAppear { cleaner.probe() }
    }
}

// 单个 App 的分组卡:头部灰条(AppIcon + App名 + 「N 份拷贝」橙徽章)+ 等宽路径行。
private struct DupGroupView: View {
    let group: DuplicateGroup
    @ObservedObject var cleaner: OpenWithCleaner

    /// 从首个 .app 拷贝读显示名;读不到则回退 bundleID。
    private var appName: String {
        if let first = group.copies.first {
            let base = first.deletingPathExtension().lastPathComponent
            if !base.isEmpty { return base }
        }
        return group.id
    }

    /// 按 bundleID 哈希取一个稳定的 hue。
    private var hue: AppIconHue {
        let all = AppIconHue.allCases
        let h = abs(group.id.hashValue) % all.count
        return all[h]
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部灰条。
            HStack(spacing: 10) {
                AppIcon("square.stack", size: 22, hue: hue)
                Text(appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MMColor.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Badge(String(format: String(localized: "openWith.copiesCount"), group.copies.count), tone: .orange)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MMColor.control)

            // 组内每行。第 0 个(排序后)视为「当前使用」,受保护。
            ForEach(Array(group.copies.enumerated()), id: \.element) { index, url in
                Rectangle()
                    .fill(MMColor.separator)
                    .frame(height: 0.5)
                DupRowView(url: url,
                           isCurrent: index == 0,
                           supported: cleaner.unregisterSupported,
                           onUnregister: { Task { _ = await cleaner.unregister(url) } },
                           onTrash: {
                               Task {
                                   if await cleaner.unregister(url) { _ = cleaner.trash(url) }
                                   cleaner.scan()
                               }
                           })
            }
        }
        .background(MMColor.card)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.5)
        )
    }
}

// 单条拷贝路径行:等宽路径(省略号截断)+ 「当前使用」绿徽章 或 反注册/反注册并移入废纸篓。
private struct DupRowView: View {
    let url: URL
    let isCurrent: Bool
    let supported: Bool
    let onUnregister: () -> Void
    let onTrash: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack")
                .font(.system(size: 14))
                .foregroundStyle(MMColor.label3)
            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MMColor.label2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if isCurrent {
                Badge(String(localized: "openWith.currentBadge"), tone: .green)
            } else {
                MMButton(String(localized: "openWith.unregister"), size: .sm, action: onUnregister)
                    .disabled(!supported)
                MMButton(String(localized: "openWith.unregisterAndTrash"), kind: .danger, size: .sm, action: onTrash)
                    .disabled(!supported)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 38)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 把家目录前缀折成 ~ 更接近设计稿。
    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        if p.hasPrefix(home) { return "~" + p.dropFirst(home.count) }
        return p
    }
}
