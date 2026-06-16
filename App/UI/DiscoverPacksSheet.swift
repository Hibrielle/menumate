// DiscoverPacksSheet.swift — 在 App 内发现社区扩展包(扫描 GitHub `menumate-pack` topic)。
// 列表里点「导入」→ 交给 PackImportSheet 预填 owner/repo,仍走完整审查流程。

import SwiftUI
import AppKit

struct DiscoverPacksSheet: View {
    let installedRepos: Set<String>     // 已装的 "owner/repo"(小写)
    let onImport: (String) -> Void      // 传 full_name
    let onClose: () -> Void

    private enum Phase: Equatable {
        case loading
        case loaded([DiscoveredPack])
        case failed(String)
    }
    @State private var phase: Phase = .loading

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: 560, height: 520)
        .background(MMColor.content)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIcon("shippingbox", size: 34, hue: .teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "discover.title"))
                    .font(.system(size: 14.5, weight: .semibold))
                Text("topic: \(PackDiscovery.topic)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(MMColor.label2)
            }
            Spacer(minLength: 0)
            MMButton(String(localized: "discover.refresh"), systemImage: "arrow.clockwise", size: .sm, action: load)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            centered { ProgressView().controlSize(.small)
                Text(String(localized: "discover.loading")).font(.system(size: 12.5)).foregroundStyle(MMColor.label2) }
        case .failed(let msg):
            centered {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 34)).foregroundStyle(MMColor.label3)
                Text(String(localized: "discover.failed")).font(.system(size: 13, weight: .medium))
                Text(msg).font(.system(size: 11)).foregroundStyle(MMColor.label3).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    MMButton(String(localized: "discover.retry"), size: .sm, action: load)
                    MMButton(String(localized: "discover.openInBrowser"), kind: .plain, size: .sm, action: openTopic)
                }.padding(.top, 4)
            }
        case .loaded(let packs) where packs.isEmpty:
            centered {
                Image(systemName: "shippingbox").font(.system(size: 34)).foregroundStyle(MMColor.label3)
                Text(String(localized: "discover.empty")).font(.system(size: 12.5)).foregroundStyle(MMColor.label2)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
        case .loaded(let packs):
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(packs.enumerated()), id: \.element.id) { i, pack in
                        if i > 0 { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
                        row(pack)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private func row(_ pack: DiscoveredPack) -> some View {
        let installed = installedRepos.contains(pack.fullName.lowercased())
        return HStack(spacing: 11) {
            AppIcon("shippingbox", size: 30, hue: .teal)
            VStack(alignment: .leading, spacing: 1) {
                Text(pack.fullName).font(.system(size: 13, weight: .semibold)).foregroundStyle(MMColor.label)
                if let d = pack.description, !d.isEmpty {
                    Text(d).font(.system(size: 11.5)).foregroundStyle(MMColor.label2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(MMColor.label3)
                Text("\(pack.stargazersCount)").font(.system(size: 11)).foregroundStyle(MMColor.label3)
            }
            if installed {
                Badge(String(localized: "discover.installed"), tone: .green)
            } else {
                MMButton(String(localized: "discover.import"), kind: .primary, size: .sm) { onImport(pack.fullName) }
            }
        }
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MMColor.separator).frame(height: 0.5)
            HStack(spacing: 9) {
                MMButton(String(localized: "discover.openInBrowser"), systemImage: "arrow.up.right.square", kind: .plain, size: .sm, action: openTopic)
                Spacer(minLength: 0)
                MMButton(String(localized: "discover.close"), size: .sm, action: onClose)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    @ViewBuilder private func centered<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 10) { c() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() {
        phase = .loading
        Task {
            do {
                let packs = try await PackDiscovery.search()
                await MainActor.run { phase = .loaded(packs) }
            } catch {
                await MainActor.run { phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func openTopic() {
        if let url = URL(string: "https://github.com/topics/\(PackDiscovery.topic)") {
            NSWorkspace.shared.open(url)
        }
    }
}
