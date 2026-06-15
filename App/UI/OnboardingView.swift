import SwiftUI
import AppKit
import FinderSync
import ServiceManagement
import MenuMateCore

// 首启引导窗 — 对照 docs/design/hifi/screen-misc.jsx OnboardWin / Onboard1 / Onboard2 / Onboard3。
// 520×480:顶部 3 个步进点(当前步 accent 长条)+ 居中标题 19/700 + 副文 12.5 灰。
// 三步用 @State step 切换。保留现有逻辑:Finder 扩展 1s 轮询、SMAppService 登录项、runDiagnosis。
struct OnboardingView: View {
    @State private var step = 0
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var accessibilityTrusted = Permissions.accessibilityTrusted
    @State private var diagnosis = OnboardingView.runDiagnosis()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            // 顶部步进点。
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(i == step ? MMColor.accent : MMColor.label4)
                        .frame(width: i == step ? 18 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)

            // 居中标题 + 副文。
            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.19) // ≈ -0.01em @ 19px
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(MMColor.label2)
                        .lineSpacing(2.5) // ≈ line-height 1.55
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            .padding(.bottom, 16)

            // 步骤内容(居中)。
            VStack(spacing: 12) {
                stepContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底栏:上一步/跳过 + 主按钮。
            HStack {
                if step > 0 {
                    MMButton(String(localized: "onboarding.previous"), kind: .plain, size: .sm) { step -= 1 }
                } else {
                    MMButton(String(localized: "onboarding.skip"), kind: .plain, size: .sm) { finish() }
                }
                Spacer()
                primaryButton
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 520, height: 480)
        .onReceive(timer) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
            accessibilityTrusted = Permissions.accessibilityTrusted
        }
        .onDisappear { timer.upstream.connect().cancel() }
    }

    // MARK: - 步进文案

    private var title: String {
        switch step {
        case 0: return String(localized: "onboarding.step1.title")
        case 1: return String(localized: "onboarding.step2.title")
        case 2: return String(localized: "onboarding.step3.title")
        default: return String(localized: "onboarding.step4.title")
        }
    }

    private var subtitle: String? {
        switch step {
        case 0: return String(localized: "onboarding.step1.subtitle")
        case 1: return String(localized: "onboarding.step2.subtitle")
        case 2: return String(localized: "onboarding.step3.subtitle")
        default: return String(localized: "onboarding.step4.subtitle")
        }
    }

    // MARK: - 步骤内容

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: step1Extension
        case 1: step2LoginItem
        case 2: step3Permissions
        default: step4Diagnosis
        }
    }

    // ① 启用扩展。
    @ViewBuilder
    private var step1Extension: some View {
        Placeholder(label: String(localized: "onboarding.step1.screenshotLabel"), height: 132)
        VStack(spacing: 10) {
            MMButton(String(localized: "onboarding.step1.openSettings"), systemImage: "arrow.up.right.square", kind: .primary) {
                FIFinderSyncController.showExtensionManagementInterface()
            }
            if extensionEnabled {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(MMColor.green)
                    Text(String(localized: "onboarding.step1.detected"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MMColor.green)
                    Text(String(localized: "onboarding.step1.autoCheck"))
                        .font(.system(size: 12))
                        .foregroundStyle(MMColor.label3)
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 16))
                        .foregroundStyle(MMColor.label3)
                    Text(String(localized: "onboarding.step1.notDetected"))
                        .font(.system(size: 12))
                        .foregroundStyle(MMColor.label3)
                    Text(String(localized: "onboarding.step1.autoCheck"))
                        .font(.system(size: 12))
                        .foregroundStyle(MMColor.label3)
                }
            }
        }
        .padding(.top, 4)
    }

    // ② 登录时启动。
    @ViewBuilder
    private var step2LoginItem: some View {
        HStack(spacing: 14) {
            AppIcon("power", size: 34, hue: .blue)
            Text(String(localized: "onboarding.step2.launchAtLogin"))
                .font(.system(size: 14, weight: .medium))
            MMSwitch($loginItemEnabled)
                .onChange(of: loginItemEnabled) { enabled in
                    if enabled { try? SMAppService.mainApp.register() }
                    else { try? SMAppService.mainApp.unregister() }
                }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(MMColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.5)
        )
        Text(String(localized: "onboarding.step2.changeLater"))
            .font(.system(size: 11))
            .foregroundStyle(MMColor.label3)
            .padding(.top, 4)
    }

    // ③ 授予权限(一次性预请求)。
    @ViewBuilder
    private var step3Permissions: some View {
        VStack(spacing: 8) {
            permissionRow(icon: "bell.badge", hue: .orange, title: String(localized: "onboarding.step3.notifications.title"),
                          desc: String(localized: "onboarding.step3.notifications.desc"))
            permissionRow(icon: "gearshape.2", hue: .blue, title: String(localized: "onboarding.step3.automation.title"),
                          desc: String(localized: "onboarding.step3.automation.desc"))
            permissionRow(icon: "accessibility", hue: .green, title: String(localized: "onboarding.step3.accessibility.title"),
                          desc: String(localized: "onboarding.step3.accessibility.desc"),
                          granted: accessibilityTrusted)
        }
        VStack(spacing: 8) {
            MMButton(String(localized: "onboarding.step3.grantAll"), systemImage: "checkmark.shield", kind: .primary) {
                Permissions.primeAll()
            }
            if !accessibilityTrusted {
                MMButton(String(localized: "onboarding.step3.openAccessibility"), kind: .plain, size: .sm) {
                    Permissions.openAccessibilitySettings()
                }
            }
            Text(String(localized: "onboarding.step3.grantHint"))
                .font(.system(size: 11))
                .foregroundStyle(MMColor.label3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(.top, 4)
    }

    // 单条权限说明行(右侧给出辅助功能的实时状态)。
    @ViewBuilder
    private func permissionRow(icon: String, hue: AppIconHue, title: String,
                               desc: String, granted: Bool? = nil) -> some View {
        HStack(spacing: 12) {
            AppIcon(icon, size: 30, hue: hue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(desc).font(.system(size: 11.5)).foregroundStyle(MMColor.label2)
            }
            Spacer(minLength: 0)
            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 16))
                    .foregroundStyle(granted ? MMColor.green : MMColor.label3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 380)
        .background(MMColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(MMColor.hairline, lineWidth: 0.5))
    }

    // ④ 环境自检。
    @ViewBuilder
    private var step4Diagnosis: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diagnosisLines.enumerated()), id: \.offset) { _, line in
                diagnosisRow(line)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MMColor.codeBg)
        .clipShape(RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
                .stroke(MMColor.border, lineWidth: 0.5)
        )
        HStack {
            Spacer()
            MMButton(String(localized: "onboarding.step4.copyDiagnosis"), systemImage: "doc.on.doc", kind: .plain, size: .sm) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diagnosis, forType: .string)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private var diagnosisLines: [String] {
        diagnosis.components(separatedBy: "\n")
    }

    // 诊断行:✓ 绿 / ! 橙 / 缩进灰。
    @ViewBuilder
    private func diagnosisRow(_ line: String) -> some View {
        let indented = line.hasPrefix("└") || line.hasPrefix(" ") || line.hasPrefix("\t")
        // 语言无关:直接比对本地化后的"告警类"诊断行(扩展未注册 / 排查 MDM),不再按中文子串匹配。
        let warning = line.contains("⚠")
            || line == String(localized: "onboarding.diag.extNotRegistered")
            || line == String(localized: "onboarding.diag.extNotEnabled")
            || line == String(localized: "onboarding.diag.noMenu")
        HStack(alignment: .top, spacing: 7) {
            if indented {
                Color.clear.frame(width: 14, height: 1)
            } else if warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(MMColor.orange)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13))
                    .foregroundStyle(MMColor.green)
            }
            Text(line)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(indented ? MMColor.label3 : MMColor.label)
                .lineSpacing(4) // ≈ line-height 1.85
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    // MARK: - 主按钮

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case 0:
            MMButton(String(localized: "onboarding.next"), kind: .primary) { step = 1 }
        case 1:
            MMButton(String(localized: "onboarding.next"), kind: .primary) { step = 2 }
        case 2:
            MMButton(String(localized: "onboarding.next"), kind: .primary) { step = 3 }
        default:
            MMButton(String(localized: "onboarding.done"), systemImage: "checkmark", kind: .primary) { finish() }
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        OnboardingWindowController.close()
    }

    // MARK: - 自检(保留现有逻辑)

    static func runDiagnosis() -> String {
        var lines: [String] = []
        if FIFinderSyncController.isExtensionEnabled {
            lines.append(String(localized: "onboarding.diag.extEnabled"))
        } else {
            lines.append(String(localized: "onboarding.diag.extNotEnabled"))
        }
        let r = ShellRunner.run("/usr/bin/pluginkit", ["-m", "-p", "com.apple.FinderSync", "-v"], timeout: 10)
        let own = PluginkitParser.parse(r.stdout).first { $0.bundleID == ExtensionManager.ownBundleID }
        if let own {
            lines.append(String(format: String(localized: "onboarding.diag.extRegistered"), "\(own.election)"))
        } else {
            lines.append(String(localized: "onboarding.diag.extNotRegistered"))
        }
        lines.append(String(localized: "onboarding.diag.deadZones"))
        lines.append(String(localized: "onboarding.diag.deadZonesNote"))
        lines.append(String(localized: "onboarding.diag.noMenu"))
        lines.append(String(localized: "onboarding.diag.noMenuNote"))
        return lines.joined(separator: "\n")
    }
}

// 灰框占位(对照设计稿 Placeholder)。
private struct Placeholder: View {
    let label: String
    var height: CGFloat = 132

    var body: some View {
        RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
            .fill(MMColor.label.opacity(0.05))
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: MMRadius.card, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(MMColor.label4)
            )
            .overlay(
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.label3)
            )
    }
}

final class OnboardingWindowController {
    private static var window: NSWindow?

    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
            w.title = String(localized: "onboarding.windowTitle")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor static func close() { window?.close() }
}
