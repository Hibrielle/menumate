// IconPicker.swift — 动作图标自定义(SF Symbol 字形 / 用户导入图片 + 配色)
// 字形写入 MenuAction.icon(.symbol);导入图片写入 .imageFile(缩放 36×36 PNG,
// 随快照 base64 传给扩展渲染)。配色写入 MenuAction.iconHue(仅影响 App 内预览/symbol 底色)。

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MenuMateCore

/// 动作可选的常用 SF Symbol 字形集(覆盖文件/脚本/转换/压缩/开发/网络等常见动作)。
let mmActionSymbols: [String] = [
    "doc.on.doc", "doc.badge.plus", "doc.on.clipboard", "doc.text", "doc.zipper",
    "folder", "folder.badge.plus", "tray", "tray.and.arrow.down", "archivebox",
    "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "function", "number",
    "photo", "photo.on.rectangle", "camera", "video", "paintpalette",
    "scissors", "wand.and.stars", "sparkles", "paintbrush", "eyedropper",
    "arrow.up.circle", "arrow.down.circle", "square.and.arrow.up", "square.and.arrow.down", "arrow.triangle.2.circlepath",
    "link", "qrcode", "globe", "network", "externaldrive",
    "lock", "lock.open", "key", "trash", "tag",
    "bolt", "hammer", "wrench.and.screwdriver", "gearshape", "command",
    "magnifyingglass", "textformat", "ruler", "calendar", "clock",
    "star", "heart", "flag", "bell", "paperplane",
    "square.grid.2x2", "square.stack", "shippingbox", "pin", "bookmark",
]

/// 编辑器里的「图标」字段:点开后选 SF Symbol 字形 / 导入图片 / 选配色。
/// icon binding 兼容 .symbol 与 .imageFile 两态:imageFile 时展示图片缩略,选符号即切回 symbol。
struct IconPickerField: View {
    @Binding var icon: IconSpec
    @Binding var hue: AppIconHue
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                ActionIconView(icon: icon, hue: hue, size: 22)
                Text(label)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(MMColor.label2)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MMColor.label3)
            }
            .padding(.leading, 6).padding(.trailing, 9).padding(.vertical, 4)
            .background(MMColor.control)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                .stroke(MMColor.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            IconPickerPopover(icon: $icon, hue: $hue)
        }
    }

    private var label: String {
        switch icon {
        case .symbol(let s): return s
        case .imageFile: return String(localized: "iconPicker.customImage")
        }
    }
}

private struct IconPickerPopover: View {
    @Binding var icon: IconSpec
    @Binding var hue: AppIconHue
    private let cols = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    private var currentSymbol: String? {
        if case .symbol(let s) = icon { return s }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "iconPicker.color"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MMColor.label2)
            HStack(spacing: 9) {
                ForEach(AppIconHue.allCases, id: \.self) { h in
                    Circle()
                        .fill(LinearGradient(colors: h.colors, startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: h == hue ? 2.5 : 0)
                            .padding(-2.5))
                        .contentShape(Circle())
                        .onTapGesture { hue = h }
                }
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 8) {
                Text(String(localized: "iconPicker.icon"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MMColor.label2)
                Spacer(minLength: 0)
                MMButton(String(localized: "iconPicker.importImage"), systemImage: "photo.badge.plus", size: .sm) { importImage() }
            }
            if case .imageFile = icon {
                HStack(spacing: 8) {
                    ActionIconView(icon: icon, hue: hue, size: 22)
                    Text(String(localized: "iconPicker.customImageHint"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(MMColor.label3)
                }
            }
            ScrollView {
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(mmActionSymbols, id: \.self) { s in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(s == currentSymbol ? Color.accentColor.opacity(0.18) : Color.clear)
                            Image(systemName: s)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(s == currentSymbol ? Color.accentColor : MMColor.label)
                        }
                        .frame(width: 32, height: 30)
                        .contentShape(Rectangle())
                        .onTapGesture { icon = .symbol(s) }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(width: 304, height: 200)
        }
        .padding(14)
        .frame(width: 332)
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let fileName = IconStore.importImage(from: url) {
            icon = .imageFile(fileName)
        }
    }
}
