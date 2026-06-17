import SwiftUI

// 设置窗:4 Tab,顺序与图标对照 ui.jsx MM_TABS。
// 早期「我的菜单」+「系统菜单」已合并为单一「右键菜单」集中入口 Hub(ScreenMenuHub)。
struct SettingsWindow: View {
    // tab 选择共享给 AppState,便于从 Hub 直接跳到「扩展包」(Tab.packs)。
    @ObservedObject private var state = AppState.shared
    var body: some View {
        TabView(selection: $state.settingsTab) {
            ScreenMenuHub()
                .tabItem { Label(String(localized: "settings.tab.contextMenu"), systemImage: "line.3.horizontal") }
                .tag(SettingsTab.contextMenu)
            ScreenPacks(packManager: AppState.shared.packManager)
                .tabItem { Label(String(localized: "settings.tab.packs"), systemImage: "shippingbox") }
                .tag(SettingsTab.packs)
            // 「打开方式」Tab 暂时屏蔽(意义不大);OpenWithTab/OpenWithCleaner 代码保留,需要时把这行恢复即可。
            // OpenWithTab().tabItem { Label(String(localized: "settings.tab.openWith"), systemImage: "square.stack") }
            GeneralTab()
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// 设置窗的 Tab 标识(用于从别处跳转,如 Hub → 扩展包)。
enum SettingsTab: Hashable { case contextMenu, packs, general }
