// DesignSystem.swift — MenuMate SwiftUI 设计系统基础层
//
// 精确复刻 docs/design/hifi/{tokens.css, ui.jsx} 与 docs/design/HANDOFF.md。
// 这是后续所有界面的共享词汇:颜色 token、圆角常量、带 MM 前缀的组件。
//
// 设计原则(对照 HANDOFF「Design Tokens」末注与本任务指引):
// - 优先用 SwiftUI/AppKit 语义色自动适配浅深 + 用户强调色;
// - 设计稿具体 hex 仅作对照,结构背景一律用 NSColor 桥接;
// - 能用系统原生控件 1:1 满足设计稿的就用原生(Toggle/Picker),无对应原生形态的自绘。

import SwiftUI
import AppKit
import MenuMateCore

// MARK: - 圆角 token(对照 ui.jsx / HANDOFF「圆角」)

enum MMRadius {
    static let window: CGFloat = 11   // Win
    static let card: CGFloat = 9      // Group / 卡片
    static let control: CGFloat = 6   // 按钮 / 文本框 / 弹出
    static let segmented: CGFloat = 7 // 分段控件
    static let badge: CGFloat = 5     // 徽章
    static let banner: CGFloat = 8    // 横幅
    static let code: CGFloat = 7      // 代码块
}

// MARK: - 颜色 token
//
// 语义色优先;结构背景用 NSColor 桥接自动适配浅深。

enum MMColor {
    // 强调与状态色 —— 直接用系统语义色,macOS 自动浅深适配 + 跟随用户强调色。
    static let accent = Color.accentColor
    static let red = Color.red
    static let orange = Color.orange
    static let green = Color.green
    static let onAccent = Color.white

    // accent 淡底(token: --accent-tint = color-mix accent 13% / 深色 26%)。
    static var accentTint: Color {
        Color.accentColor.opacity(MMColor.isDark ? 0.26 : 0.13)
    }

    // 文本三阶(label / label-2 / label-3)。
    static let label = Color.primary
    static let label2 = Color.secondary
    static let label3 = Color(nsColor: .tertiaryLabelColor)
    static let label4 = Color(nsColor: .quaternaryLabelColor)

    // 结构背景(NSColor 桥接)。
    static let card = Color(nsColor: .controlBackgroundColor)     // 分组卡片
    static let content = Color(nsColor: .windowBackgroundColor)   // 内容区
    static let control = Color(nsColor: .controlColor)            // 控件底(default 按钮/弹出)
    static let field = Color(nsColor: .textBackgroundColor)       // 输入框
    static let separator = Color(nsColor: .separatorColor)        // 分隔线

    // hairline / border:用 separator 的低透明度近似(token 细描边 0.5px)。
    static let hairline = Color(nsColor: .separatorColor).opacity(0.7)
    static let border = Color(nsColor: .separatorColor)

    // 代码块底(token --code-bg);用更暗的内容色近似。
    static var codeBg: Color { Color(nsColor: .textBackgroundColor) }

    /// 当前是否深色外观(用于派生 tint / 高亮色,SwiftUI 静态属性无法读 Environment 故走 NSApp)。
    static var isDark: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// 0.5px hairline 在 Retina 上的实际渲染宽度。
private let kHairline: CGFloat = 0.5

// MARK: - AppIcon(圆角方 + 渐变底 + 居中白色 SF Symbol + 顶部内高光)
//
// 对照 ui.jsx AppIcon:radius=size*0.235,160° 线性渐变,symbol=size*0.56,
// inset 顶部高光 + 外部 0.5px 投影。

enum AppIconHue: String, CaseIterable {
    case blue, gray, green, orange, purple, red, teal, pink

    /// 160° 渐变的两端色(对照 ui.jsx grads)。
    var colors: [Color] {
        switch self {
        case .blue:   return [Color(hex: 0x3aa0ff), Color(hex: 0x0a6dff)]
        case .gray:   return [Color(hex: 0x9aa0a8), Color(hex: 0x6c727b)]
        case .green:  return [Color(hex: 0x46d36a), Color(hex: 0x21a843)]
        case .orange: return [Color(hex: 0xffb43a), Color(hex: 0xff8a00)]
        case .purple: return [Color(hex: 0xb07bff), Color(hex: 0x7a3df0)]
        case .red:    return [Color(hex: 0xff6a60), Color(hex: 0xff2d22)]
        case .teal:   return [Color(hex: 0x48d6c8), Color(hex: 0x16a99a)]
        case .pink:   return [Color(hex: 0xff7ab0), Color(hex: 0xff3d84)]
        }
    }
}

struct AppIcon: View {
    let icon: String
    var size: CGFloat = 30
    var hue: AppIconHue = .gray

    init(_ icon: String, size: CGFloat = 30, hue: AppIconHue = .gray) {
        self.icon = icon
        self.size = size
        self.hue = hue
    }

    var body: some View {
        let radius = size * 0.235
        // 160°: CSS 角从 12 点顺时针;近似为左上→右下偏向的对角渐变。
        let grad = LinearGradient(
            colors: hue.colors,
            startPoint: UnitPoint(x: 0.18, y: 0.0),
            endPoint: UnitPoint(x: 0.82, y: 1.0)
        )
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(grad)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay( // 顶部内高光
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: kHairline
                    )
            )
            .shadow(color: Color.black.opacity(0.2), radius: 0.5, x: 0, y: 0.5)
    }
}

// MARK: - ActionIconView(动作图标:SF Symbol 渐变方 或 用户导入图片)
//
// .symbol(name)    → 现有 AppIcon(渐变底 + 白 symbol)。
// .imageFile(name) → 圆角方裁切的用户图片(radius=size*0.235,scaledToFill 居中),
//                    加与 AppIcon 同款描边/顶部内高光;图片缺失回退 AppIcon("photo")。

struct ActionIconView: View {
    let icon: IconSpec
    var hue: AppIconHue = .gray
    var size: CGFloat = 30

    init(icon: IconSpec, hue: AppIconHue = .gray, size: CGFloat = 30) {
        self.icon = icon
        self.hue = hue
        self.size = size
    }

    var body: some View {
        switch icon {
        case .symbol(let name):
            AppIcon(name, size: size, hue: hue)
        case .imageFile(let fileName):
            if let nsImage = IconStore.loadNSImage(fileName) {
                let radius = size * 0.235
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay( // 顶部内高光(同 AppIcon)
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.clear],
                                    startPoint: .top, endPoint: .center
                                ),
                                lineWidth: kHairline
                            )
                    )
                    .overlay( // 外描边,贴合图片边缘
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(MMColor.border, lineWidth: kHairline)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 0.5, x: 0, y: 0.5)
            } else {
                AppIcon("photo", size: size, hue: hue)   // 图片缺失回退
            }
        }
    }
}

// MARK: - MMSwitch(系统原生开关,绿开灰关)
//
// 用系统 Toggle(.switch),完全满足设计稿 38×23 绿/灰开关形态。

struct MMSwitch: View {
    @Binding var isOn: Bool
    var scale: CGFloat = 1

    init(_ isOn: Binding<Bool>, scale: CGFloat = 1) {
        self._isOn = isOn
        self.scale = scale
    }

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(scale)
    }
}

// MARK: - MMButton(真实 Button,对照 ui.jsx kinds 表)

enum MMButtonKind {
    case normal     // default: 控件底 + label 字
    case primary    // accent 填充 + 白字
    case danger     // 控件底 + 红字
    case dangerFill // 红底 + 白字
    case tinted     // accentTint 底 + accent 字
    case plain      // 透明 + accent 字
}

enum MMButtonSize {
    case sm, md
    var font: Font { self == .sm ? .system(size: 12, weight: .medium) : .system(size: 13, weight: .medium) }
    var hPad: CGFloat { self == .sm ? 10 : 13 }
    var vPad: CGFloat { self == .sm ? 3 : 5 }
    var plainHPad: CGFloat { self == .sm ? 4 : 6 } // plain 收窄左右内距
}

struct MMButton: View {
    let title: String
    var systemImage: String?
    var kind: MMButtonKind = .normal
    var size: MMButtonSize = .md
    var action: () -> Void = {}

    init(_ title: String,
         systemImage: String? = nil,
         kind: MMButtonKind = .normal,
         size: MMButtonSize = .md,
         action: @escaping () -> Void = {}) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(size.font)
                }
                Text(title)
                    .font(size.font)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .plain ? size.plainHPad : size.hPad)
            .padding(.vertical, size.vPad)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(strokeOverlay)
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch kind {
        case .normal:     return MMColor.label
        case .primary:    return MMColor.onAccent
        case .danger:     return MMColor.red
        case .dangerFill: return MMColor.onAccent
        case .tinted:     return MMColor.accent
        case .plain:      return MMColor.accent
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .normal, .danger: MMColor.control
        case .primary:         MMColor.accent
        case .dangerFill:      MMColor.red
        case .tinted:          MMColor.accentTint
        case .plain:           Color.clear
        }
    }

    @ViewBuilder private var strokeOverlay: some View {
        switch kind {
        case .normal, .danger:
            RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                .stroke(MMColor.border, lineWidth: kHairline)
        default:
            EmptyView()
        }
    }
}

// MARK: - Segmented(系统原生分段控件)

struct Segmented: View {
    let options: [String]
    @Binding var selection: Int

    init(_ options: [String], selection: Binding<Int>) {
        self.options = options
        self._selection = selection
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i]).tag(i)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}

// MARK: - FlowLayout(自动换行的水平排布,用于多选 chips)
//
// macOS 13+ 的 Layout 协议实现:子视图按本征尺寸从左到右排,超出可用宽度则换行。
// 需要一个有界宽度(调用方用 .frame(width:) 约束)才能正确换行。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - MMPopup(展示态胶囊 + 蓝色 chevron.up.chevron.down 方块尾标)
//
// 对照 ui.jsx Popup:控件底胶囊,尾部 16×16 accent 圆角方内白色上下箭头。
// 仅展示组件;需要真实交互的调用方自行用 Menu / Picker(.menu)。

struct MMPopup: View {
    let value: String
    var width: CGFloat?

    init(_ value: String, width: CGFloat? = nil) {
        self.value = value
        self.width = width
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(MMColor.label)
                .lineLimit(1)
                .truncationMode(.tail)
            if width != nil { Spacer(minLength: 0) }
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(MMColor.accent)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 16, height: 16)
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
        .background(MMColor.control)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                .stroke(MMColor.border, lineWidth: kHairline)
        )
    }
}

// MARK: - MMField(圆角描边输入框 + 只读展示重载)
//
// 对照 ui.jsx Field:圆角 6 描边,mono 用等宽字体。

struct MMField: View {
    @Binding var text: String
    var placeholder: String = ""
    var mono: Bool = false
    var width: CGFloat?

    /// 可编辑输入框。
    init(_ text: Binding<String>, placeholder: String = "", mono: Bool = false, width: CGFloat? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.mono = mono
        self.width = width
    }

    /// 只读展示重载(传入固定字符串)。
    init(value: String, placeholder: String = "", mono: Bool = false, width: CGFloat? = nil) {
        self._text = .constant(value)
        self.placeholder = placeholder
        self.mono = mono
        self.width = width
    }

    private var font: Font {
        mono ? .system(size: 13, design: .monospaced) : .system(size: 13)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(MMColor.label)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(width: width, alignment: .leading)
            .background(MMColor.field)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                    .stroke(MMColor.border, lineWidth: kHairline)
            )
    }
}

// MARK: - Badge(胶囊徽章,对照 ui.jsx tones)

enum BadgeTone {
    case gray, accent, green, orange, red

    var fg: Color {
        switch self {
        case .gray:   return MMColor.label2
        case .accent: return MMColor.accent
        case .green:  return MMColor.green
        case .orange: return MMColor.orange
        case .red:    return MMColor.red
        }
    }
    var bg: Color {
        switch self {
        case .gray:   return MMColor.label.opacity(0.08)
        case .accent: return MMColor.accentTint
        case .green:  return MMColor.green.opacity(MMColor.isDark ? 0.22 : 0.16)
        case .orange: return MMColor.orange.opacity(MMColor.isDark ? 0.22 : 0.16)
        case .red:    return MMColor.red.opacity(MMColor.isDark ? 0.22 : 0.14)
        }
    }
}

struct Badge: View {
    let text: String
    var tone: BadgeTone = .gray

    init(_ text: String, tone: BadgeTone = .gray) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.1)
            .foregroundStyle(tone.fg)
            .padding(.vertical, 1.5)
            .padding(.horizontal, 7)
            .background(tone.bg)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
            .fixedSize()
    }
}

// MARK: - MMGroup(分组列表卡片,直接子视图间自动插分隔线)
//
// 对照 ui.jsx Group:卡片圆角 9 + 0.5px hairline 描边,
// 行间 0.5px 分隔(左缩进 14);header 11/600 大写 letterSpacing;footer 11.5 灰。
// 用 _VariadicView 在直接子视图间插分隔线(无需调用方手动加 Divider)。

struct MMGroup<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(header: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.44) // ≈ .04em @ 11px
                    .foregroundStyle(MMColor.label2)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            _VariadicView.Tree(MMGroupLayout()) {
                content
            }
            .background(MMColor.card)
            .clipShape(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
                    .stroke(MMColor.hairline, lineWidth: kHairline)
            )
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(MMColor.label2)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }
}

/// 在每个直接子视图之间插入左缩进 14 的 0.5px 分隔线。
private struct MMGroupLayout: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                if index > 0 {
                    Rectangle()
                        .fill(MMColor.separator)
                        .frame(height: kHairline)
                        .padding(.leading, 14)
                }
                child
            }
        }
    }
}

// MARK: - MMRow(水平列表行,pad 8×14 gap 10 字号 13)

struct MMRow<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 13))
        .foregroundStyle(MMColor.label)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Banner(警示横幅)
//
// 对照 ui.jsx Banner:圆角 8 + 低透明度 tone 底 + 0.5px 描边,
// 左 SF Symbol + 文本 12.5 + 右尾。

enum BannerTone {
    case orange, red, accent, info

    var fg: Color {
        switch self {
        case .orange: return MMColor.orange
        case .red:    return MMColor.red
        case .accent: return MMColor.accent
        case .info:   return MMColor.label2
        }
    }
    var bg: Color {
        switch self {
        case .orange: return MMColor.orange.opacity(MMColor.isDark ? 0.20 : 0.14)
        case .red:    return MMColor.red.opacity(MMColor.isDark ? 0.20 : 0.12)
        case .accent: return MMColor.accentTint
        case .info:   return MMColor.label.opacity(0.07)
        }
    }
}

struct Banner<Trailing: View>: View {
    let text: String
    var tone: BannerTone = .orange
    var systemImage: String = "exclamationmark.triangle.fill"
    @ViewBuilder var trailing: Trailing

    init(_ text: String,
         tone: BannerTone = .orange,
         systemImage: String = "exclamationmark.triangle.fill",
         @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(tone.fg)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(MMColor.label)
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(tone.bg)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.banner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.banner, style: .continuous)
                .stroke(MMColor.border, lineWidth: kHairline)
        )
    }
}

extension Banner where Trailing == EmptyView {
    /// 无 trailing 的便捷重载。
    init(_ text: String,
         tone: BannerTone = .orange,
         systemImage: String = "exclamationmark.triangle.fill") {
        self.init(text, tone: tone, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - CodeBlock(终端条 + 行号 + 等宽代码 + 基础 zsh 高亮)
//
// 对照 ui.jsx CodeBlock + hl():顶部 terminal 图标 + lang 条;
// 行号右对齐灰;代码 11.5/1.65;注释灰 / 关键字 / $变量 / 字符串高亮;只读。

struct CodeBlock: View {
    let code: String
    var lang: String = "zsh"
    var maxHeight: CGFloat?

    init(_ code: String, lang: String = "zsh", maxHeight: CGFloat? = nil) {
        self.code = code
        self.lang = lang
        self.maxHeight = maxHeight
    }

    private var lines: [String] {
        code.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 终端条
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.label2)
                Text(lang)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MMColor.label2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MMColor.separator).frame(height: kHairline)
            }

            // 代码区(行号 + 高亮)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, ln in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(i + 1)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(MMColor.label4)
                                .frame(width: 30, alignment: .trailing)
                                .padding(.trailing, 12)
                            Text(MMSyntax.highlightZsh(ln))
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineSpacing(11.5 * 0.65) // line-height 1.65
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.trailing, 12)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: maxHeight)
        }
        .background(MMColor.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.code, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.code, style: .continuous)
                .stroke(MMColor.border, lineWidth: kHairline)
        )
    }
}

/// 基础 zsh 高亮(对照 ui.jsx hl):注释 / 关键字 / $变量 / 字符串。
enum MMSyntax {
    private static let keywords: Set<String> = [
        "if", "then", "fi", "for", "do", "done", "in", "local", "function",
        "return", "case", "esac", "while", "echo", "exit", "set",
    ]
    private static let commentColor = Color(nsColor: .tertiaryLabelColor)
    private static let keywordColor = Color(hex: 0xa548c0)  // 紫
    private static let varColor = Color(hex: 0x2c8c5a)      // 绿
    private static let stringColor = Color(hex: 0xc9762e)   // 橙棕

    static func highlightZsh(_ line: String) -> AttributedString {
        var result = AttributedString(line)
        result.foregroundColor = MMColor.label

        // 整行注释(以可选空白 + # 开头):整行灰。
        if let firstNonWS = line.first(where: { !$0.isWhitespace }), firstNonWS == "#" {
            result.foregroundColor = commentColor
            return result
        }

        // 字符串("..." 或 '...')。
        apply(pattern: "\"[^\"]*\"|'[^']*'", to: &result, in: line, color: stringColor)
        // 关键字(词边界)。
        for kw in keywords {
            apply(pattern: "\\b\(kw)\\b", to: &result, in: line, color: keywordColor)
        }
        // $变量(${VAR} / $VAR / $@ / $1)。
        apply(pattern: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?|\\$@|\\$[0-9]", to: &result, in: line, color: varColor)
        // 行内注释( 空白 + #... 到行尾)。
        apply(pattern: "(?<=\\s)#.*$", to: &result, in: line, color: commentColor)

        return result
    }

    private static func apply(pattern: String, to attr: inout AttributedString, in source: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard let r = Range(m.range, in: source),
                  let lo = AttributedString.Index(r.lowerBound, within: attr),
                  let hi = AttributedString.Index(r.upperBound, within: attr) else { continue }
            attr[lo..<hi].foregroundColor = color
        }
    }
}

// MARK: - ControlDot(可控程度模型 ●◐○)
//
// HANDOFF 核心概念:full=实心 accent;hide=橙描边 + 左半填充半月;opaque=灰空心环。

enum ControlDegree {
    case full    // ● 自有/扩展包动作:完全掌控
    case hide    // ◐ 系统服务/快速操作:仅可显示/隐藏
    case opaque  // ○ 第三方扩展:仅整体开关
}

struct ControlDot: View {
    let kind: ControlDegree
    var size: CGFloat = 10

    init(_ kind: ControlDegree, size: CGFloat = 10) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        switch kind {
        case .full:
            Circle()
                .fill(MMColor.accent)
                .frame(width: size, height: size)
        case .hide:
            // 橙描边环 + 左半填充半月。
            ZStack {
                Circle()
                    .trim(from: 0.5, to: 1.0) // 左半(从底经左到顶)
                    .fill(MMColor.orange)
                Circle()
                    .stroke(MMColor.orange, lineWidth: max(1, size * 0.13))
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(180)) // 让填充落在视觉左半
        case .opaque:
            Circle()
                .stroke(MMColor.label3, lineWidth: max(1, size * 0.13))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Grip(2×3 拖拽手柄)
//
// 6 个小圆点,.secondary opacity .45。

struct Grip: View {
    var dotSize: CGFloat = 2.5
    var spacing: CGFloat = 3

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: spacing) {
                    Circle().frame(width: dotSize, height: dotSize)
                    Circle().frame(width: dotSize, height: dotSize)
                }
            }
        }
        .foregroundStyle(MMColor.label2.opacity(0.45))
    }
}

// MARK: - MMDot(小圆点 + 卡片色描边,如"有更新"蓝点)
//
// 对照 ui.jsx Dot:实心圆 + 2px 卡片色外环。

struct MMDot: View {
    var color: Color = .accentColor
    var size: CGFloat = 8

    init(color: Color = .accentColor, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle().stroke(MMColor.card, lineWidth: 2)
            )
    }
}

// MARK: - Color(hex:) 辅助(仅用于设计稿具体色对照,如 AppIcon 渐变 / 代码高亮)

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Preview(铺主要组件)

#Preview("Design System") {
    DesignSystemPreview()
        .frame(width: 560)
        .padding(20)
        .background(MMColor.content)
}

private struct DesignSystemPreview: View {
    @State private var on1 = true
    @State private var on2 = false
    @State private var seg = 0
    @State private var fieldText = ""
    @State private var monoText = "~/Library/Scripts"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                // AppIcon 全色板
                HStack(spacing: 10) {
                    ForEach(AppIconHue.allCases, id: \.self) { hue in
                        AppIcon("photo", size: 30, hue: hue)
                    }
                }

                // 按钮
                HStack(spacing: 8) {
                    MMButton("普通")
                    MMButton("主要", kind: .primary)
                    MMButton("危险", kind: .danger)
                    MMButton("危险填充", kind: .dangerFill)
                    MMButton("淡色", kind: .tinted)
                    MMButton("纯文本", kind: .plain)
                }
                HStack(spacing: 8) {
                    MMButton("小号", systemImage: "trash", size: .sm)
                    MMButton("中号", systemImage: "arrow.clockwise", kind: .primary, size: .md)
                }

                // 分段 + 弹出 + 开关
                HStack(spacing: 12) {
                    Segmented(["全部", "仅 MenuMate", "仅系统"], selection: $seg)
                        .frame(width: 240)
                    MMSwitch($on1)
                    MMSwitch($on2)
                }
                MMPopup("文件和文件夹", width: 180)

                // 字段
                HStack(spacing: 8) {
                    MMField($fieldText, placeholder: "菜单标题")
                        .frame(width: 160)
                    MMField($monoText, mono: true, width: 200)
                    MMField(value: "只读", width: 80)
                }

                // 徽章
                HStack(spacing: 6) {
                    Badge("dev-tools")
                    Badge("有更新 v2", tone: .accent)
                    Badge("当前使用", tone: .green)
                    Badge("3 份拷贝", tone: .orange)
                    Badge("默认禁用", tone: .red)
                }

                // 控制点 + 抓手 + 蓝点
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        ControlDot(.full); ControlDot(.hide); ControlDot(.opaque)
                    }
                    Grip()
                    MMDot()
                    MMDot(color: .orange, size: 10)
                }

                // 分组列表
                MMGroup(header: "右键菜单", footer: "拖动排序 · 点选编辑。") {
                    MMRow {
                        Grip()
                        AppIcon("photo", size: 20, hue: .blue)
                        Text("图片转换")
                        Spacer()
                        MMSwitch($on1, scale: 0.85)
                    }
                    MMRow {
                        ControlDot(.hide)
                        Image(systemName: "square.grid.2x2")
                        Text("快速操作")
                        Spacer()
                        Badge("系统服务", tone: .orange)
                    }
                    MMRow {
                        ControlDot(.opaque)
                        Image(systemName: "lock.fill")
                        Text("第三方扩展")
                        Spacer()
                        MMSwitch($on2, scale: 0.85)
                    }
                }

                // 横幅
                Banner("该仓库的脚本将以你的用户权限运行,请逐一审查。", tone: .red)
                Banner("脚本来自扩展包,只读。fork 仓库后可重新导入。", tone: .accent, systemImage: "info.circle.fill") {
                    MMButton("查看", kind: .plain, size: .sm)
                }

                // 代码块
                CodeBlock("""
                #!/bin/zsh
                # 把图片转成 png
                for f in "$@"; do
                  sips -s format png "$f" --out "${f%.*}.png"
                done
                echo "完成"
                """, maxHeight: 140)
            }
        }
    }
}
