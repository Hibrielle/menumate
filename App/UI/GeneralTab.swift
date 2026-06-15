import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers
import MenuMateCore

// 通用 Tab — 对照 docs/design/hifi/screen-system.jsx ScreenGeneral + DestructiveDialog。
// 分组列表(登录时启动 / 脚本·模板文件夹 / 恢复出厂预设·重新运行引导)+ 底部版本灰字。
// 破坏性确认为自绘 overlay,复刻 DestructiveDialog(红圆底三角 + 标题 + 「此操作不可撤销」加粗 + 竖排按钮)。
struct GeneralTab: View {
    @State private var loginItemEnabled = SMAppService.mainApp.status == .enabled
    @State private var confirmRestore = false
    @State private var terminalID = AppPrefs.terminalBundleID
    @State private var editorID = AppPrefs.editorBundleID

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return String(format: String(localized: "general.versionFooter"), v)
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 登录时启动(无 header)。
                    MMGroup {
                        MMRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: "general.launchAtLogin"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(MMColor.label)
                                Text(String(localized: "general.launchAtLoginDesc"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MMColor.label3)
                            }
                            Spacer(minLength: 0)
                            MMSwitch($loginItemEnabled, scale: 0.78)
                                .onChange(of: loginItemEnabled) { enabled in
                                    if enabled { try? SMAppService.mainApp.register() }
                                    else { try? SMAppService.mainApp.unregister() }
                                }
                        }
                    }

                    // 脚本。
                    MMGroup(header: String(localized: "general.scripts")) {
                        MMRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: "general.scriptsFolder"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(MMColor.label)
                                Text(AppPaths.scriptsDirectory().path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MMColor.label3)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            MMButton(String(localized: "general.openInFinder"), systemImage: "folder", size: .sm) {
                                NSWorkspace.shared.open(AppPaths.scriptsDirectory())
                            }
                        }
                        MMRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: "general.templatesFolder"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(MMColor.label)
                                Text(String(localized: "general.templatesFolderDesc"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MMColor.label3)
                            }
                            Spacer(minLength: 0)
                            MMButton(String(localized: "general.openInFinder"), systemImage: "folder", size: .sm) {
                                NSWorkspace.shared.open(AppPaths.templatesDirectory())
                            }
                        }
                    }

                    // 外部工具(默认终端 / 编辑器)——喂给「在终端打开 / 用编辑器打开」预设。
                    MMGroup(header: String(localized: "general.externalTools"), footer: String(localized: "general.externalToolsFooter")) {
                        toolRow(title: String(localized: "general.defaultTerminal"),
                                current: terminalID,
                                candidates: AppDetect.installed(AppDetect.terminalCandidates),
                                fallbackName: String(localized: "general.fallbackTerminal")) { picked in
                            terminalID = picked; AppPrefs.terminalBundleID = picked
                        }
                        toolRow(title: String(localized: "general.defaultEditor"),
                                current: editorID,
                                candidates: AppDetect.installed(AppDetect.editorCandidates),
                                fallbackName: String(localized: "general.fallbackEditor")) { picked in
                            editorID = picked; AppPrefs.editorBundleID = picked
                        }
                    }

                    // 维护。
                    MMGroup(header: String(localized: "general.maintenance")) {
                        MMRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: "general.restorePresets"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(MMColor.label)
                                Text(String(localized: "general.restorePresetsDesc"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MMColor.label3)
                            }
                            Spacer(minLength: 0)
                            MMButton(String(localized: "general.restore"), kind: .danger, size: .sm) {
                                confirmRestore = true
                            }
                        }
                        MMRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(String(localized: "general.rerunOnboarding"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(MMColor.label)
                            }
                            Spacer(minLength: 0)
                            MMButton(String(localized: "general.rerun"), size: .sm) {
                                UserDefaults.standard.set(false, forKey: "onboardingDone")
                                OnboardingWindowController.show()
                            }
                        }
                    }

                    // 底部版本灰字居中。
                    Text(versionString)
                        .font(.system(size: 11))
                        .foregroundStyle(MMColor.label3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(MMColor.content)

            // 破坏性确认对话框(自绘 overlay)。
            if confirmRestore {
                DestructiveRestoreDialog(
                    isPresented: $confirmRestore,
                    onConfirm: { PresetSeeder.restorePresets(state: AppState.shared) }
                )
            }
        }
    }

    // 默认终端 / 编辑器选择行:Menu 列出已装 App + 跟随默认 + 自定义…。
    @ViewBuilder
    private func toolRow(title: String, current: String?, candidates: [DetectedApp],
                         fallbackName: String, onPick: @escaping (String?) -> Void) -> some View {
        let currentName = current.map { AppDetect.displayName(for: $0) }
            ?? String(format: String(localized: "general.followDefault"), fallbackName)
        MMRow {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(MMColor.label)
            Spacer(minLength: 0)
            Menu {
                Button(String(format: String(localized: "general.followDefault"), fallbackName)) { onPick(nil) }
                if !candidates.isEmpty { Divider() }
                ForEach(candidates) { app in
                    Button {
                        onPick(app.bundleID)
                    } label: {
                        if app.bundleID == current { Label(app.name, systemImage: "checkmark") }
                        else { Text(app.name) }
                    }
                }
                Divider()
                Button(String(localized: "general.custom")) { pickCustomApp(onPick) }
            } label: {
                MMPopup(currentName, width: 200)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func pickCustomApp(_ onPick: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bid = Bundle(url: url)?.bundleIdentifier else { return }
        onPick(bid)
    }
}

// 居中卡 280 — 复刻 DestructiveDialog:遮罩 + 红圆底警告三角 + 标题 + 影响说明(含加粗「此操作不可撤销」)+ 竖排按钮。
private struct DestructiveRestoreDialog: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    private var impactText: AttributedString {
        var s = AttributedString(String(localized: "general.restoreImpact"))
        var bold = AttributedString(String(localized: "general.restoreIrreversible"))
        bold.font = .system(size: 11.5, weight: .bold)
        s.append(bold)
        return s
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(MMColor.red.opacity(MMColor.isDark ? 0.22 : 0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(MMColor.red)
                }

                Text(String(localized: "general.restoreConfirmTitle"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MMColor.label)

                Text(impactText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(MMColor.label2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)

                VStack(spacing: 7) {
                    Button {
                        onConfirm()
                        isPresented = false
                    } label: {
                        Text(String(localized: "general.restorePresets"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MMColor.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(MMColor.red)
                            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        isPresented = false
                    } label: {
                        Text(String(localized: "general.cancel"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MMColor.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(MMColor.control)
                            .clipShape(RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: MMRadius.control, style: .continuous)
                                    .stroke(MMColor.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(width: 280)
            .background(MMColor.content)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 8)
        }
    }
}
