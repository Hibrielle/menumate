import SwiftUI

// 设置窗:4 Tab,顺序与图标对照 ui.jsx MM_TABS。
// 早期「我的菜单」+「系统菜单」已合并为单一「右键菜单」集中入口 Hub(ScreenMenuHub)。
struct SettingsWindow: View {
    var body: some View {
        TabView {
            ScreenMenuHub()
                .tabItem { Label(String(localized: "settings.tab.contextMenu"), systemImage: "line.3.horizontal") }
            ScreenPacks(packManager: AppState.shared.packManager)
                .tabItem { Label(String(localized: "settings.tab.packs"), systemImage: "shippingbox") }
            // 「打开方式」Tab 暂时屏蔽(意义不大);OpenWithTab/OpenWithCleaner 代码保留,需要时把这行恢复即可。
            // OpenWithTab().tabItem { Label(String(localized: "settings.tab.openWith"), systemImage: "square.stack") }
            GeneralTab()
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
