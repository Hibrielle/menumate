import XCTest
@testable import MenuMateCore

/// ServiceStatusEditor：pbs NSServicesStatus 的唯一性感知匹配 + 就地改值。
/// 真实碰撞场景（macOS 15 实测）：
/// - Terminal 两个服务共享 (com.apple.Terminal, newTerminalAtFolder)
/// - 所有 Automator 快捷操作共享 ((null), runWorkflowAsService)
final class ServiceStatusEditorTests: XCTestCase {

    // MARK: - 常用键

    private let termA = "com.apple.Terminal - New Terminal at Folder - newTerminalAtFolder"
    private let termB = "com.apple.Terminal - New Terminal Tab at Folder - newTerminalAtFolder"

    /// 旧版/系统写的全 false 禁用形状
    private var bareDisabled: [String: Any] {
        ["enabled_context_menu": false,
         "presentation_modes": ["ContextMenu": false, "ServicesMenu": false]]
    }

    private func disableTermA(_ status: [String: Any], unique: Bool) -> [String: Any] {
        ServiceStatusEditor.apply(enabled: false, to: status,
                                  bundleID: "com.apple.Terminal", menuTitle: "New Terminal at Folder",
                                  localizedTitle: nil, message: "newTerminalAtFolder", isPairUnique: unique)
    }

    private func enableTermA(_ status: [String: Any], unique: Bool) -> [String: Any] {
        ServiceStatusEditor.apply(enabled: true, to: status,
                                  bundleID: "com.apple.Terminal", menuTitle: "New Terminal at Folder",
                                  localizedTitle: nil, message: "newTerminalAtFolder", isPairUnique: unique)
    }

    private func termADisabled(_ status: [String: Any], unique: Bool) -> Bool {
        ServiceStatusEditor.isDisabled(in: status,
                                       bundleID: "com.apple.Terminal", menuTitle: "New Terminal at Folder",
                                       localizedTitle: nil, message: "newTerminalAtFolder", isPairUnique: unique)
    }

    // MARK: - 唯一 pair：disable 合成禁用条目，enable 整键删除

    func testUniquePairDisableSynthesizesDisabledEntryAndEnableRemovesIt() {
        let disabled = disableTermA([:], unique: true)
        let entry = disabled[termA] as? [String: Any]
        XCTAssertNotNil(entry, "应在 default 标题精确键下合成条目")
        XCTAssertEqual(entry?["enabled_context_menu"] as? Bool, false)
        let pm = entry?["presentation_modes"] as? [String: Any]
        XCTAssertEqual(pm?["ContextMenu"] as? Bool, false)
        XCTAssertEqual(pm?["ServicesMenu"] as? Bool, false)
        XCTAssertNil(entry?["key_equivalent"], "合成条目不应引入 key_equivalent")
        XCTAssertTrue(termADisabled(disabled, unique: true))

        let enabled = enableTermA(disabled, unique: true)
        XCTAssertNil(enabled[termA], "无其他状态的禁用条目，enable 应整键删除")
        XCTAssertTrue(enabled.isEmpty)
        XCTAssertFalse(termADisabled(enabled, unique: true))
    }

    func testEnableWithNoMatchedKeyIsNoOp() {
        let status: [String: Any] = ["com.other.App - Foo - doFoo": bareDisabled]
        let out = enableTermA(status, unique: true)
        XCTAssertEqual(out as NSDictionary, status as NSDictionary, "enable 不应合成新键，也不应动别人")
    }

    // MARK: - 非唯一 pair：兄弟服务隔离（CRITICAL bug 的核心回归）

    func testNonUniqueSiblingNotReportedDisabled() {
        // 用户在系统设置里禁用了 B；A 不应被串报为禁用
        let status: [String: Any] = [termB: bareDisabled]
        XCTAssertFalse(termADisabled(status, unique: false),
                       "非唯一 pair 禁止模糊匹配：B 的禁用不应串到 A")
    }

    func testNonUniqueDisableEnableDoesNotTouchSibling() {
        let siblingEntry: [String: Any] =
            ["enabled_context_menu": false, "enabled_services_menu": false,
             "presentation_modes": ["ContextMenu": false, "ServicesMenu": false]]
        let status: [String: Any] = [termB: siblingEntry]

        // 禁用 A：只写 A 的精确键，B 原样保留
        let disabled = disableTermA(status, unique: false)
        XCTAssertEqual(disabled[termB] as? NSDictionary, siblingEntry as NSDictionary, "B 的条目必须逐字节不变")
        XCTAssertEqual((disabled[termA] as? [String: Any])?["enabled_context_menu"] as? Bool, false)

        // 启用 A：只删 A 的键，B 仍然保留（不再有"先全删后重写"的串改）
        let enabled = enableTermA(disabled, unique: false)
        XCTAssertNil(enabled[termA])
        XCTAssertEqual(enabled[termB] as? NSDictionary, siblingEntry as NSDictionary,
                       "enable A 不得删除/复活兄弟服务 B 的禁用状态")
    }

    func testAutomatorNullBundleIDSiblingsIsolated() {
        // 所有 Automator 快捷操作共享 (null) + runWorkflowAsService
        let keyA = "(null) - Resize Images - runWorkflowAsService"
        let keyB = "(null) - Convert to PDF - runWorkflowAsService"
        let status: [String: Any] = [keyB: bareDisabled]

        XCTAssertFalse(ServiceStatusEditor.isDisabled(in: status, bundleID: nil,
                                                      menuTitle: "Resize Images", localizedTitle: nil,
                                                      message: "runWorkflowAsService", isPairUnique: false))
        let disabled = ServiceStatusEditor.apply(enabled: false, to: status, bundleID: nil,
                                                 menuTitle: "Resize Images", localizedTitle: nil,
                                                 message: "runWorkflowAsService", isPairUnique: false)
        XCTAssertNotNil(disabled[keyA])
        XCTAssertEqual(disabled[keyB] as? NSDictionary, bareDisabled as NSDictionary)

        let enabled = ServiceStatusEditor.apply(enabled: true, to: disabled, bundleID: nil,
                                                menuTitle: "Resize Images", localizedTitle: nil,
                                                message: "runWorkflowAsService", isPairUnique: false)
        XCTAssertNil(enabled[keyA])
        XCTAssertNotNil(enabled[keyB], "启用 A 不能顺手抹掉 B 的禁用")
    }

    // MARK: - key_equivalent / enabled_services_menu 保全（IMPORTANT bug 的核心回归）

    func testDisablePreservesKeyEquivalentAndServicesMenuState() {
        let status: [String: Any] = [termA: ["key_equivalent": "@$T",
                                             "enabled_services_menu": true,
                                             "presentation_modes": ["ServicesMenu": true]]]
        let out = disableTermA(status, unique: true)
        let entry = out[termA] as? [String: Any]
        XCTAssertEqual(entry?["key_equivalent"] as? String, "@$T", "禁用必须保留用户快捷键")
        XCTAssertEqual(entry?["enabled_services_menu"] as? Bool, true, "enabled_services_menu 不得被覆盖")
        XCTAssertEqual(entry?["enabled_context_menu"] as? Bool, false)
        let pm = entry?["presentation_modes"] as? [String: Any]
        XCTAssertEqual(pm?["ContextMenu"] as? Bool, false)
        XCTAssertEqual(pm?["ServicesMenu"] as? Bool, true, "presentation_modes.ServicesMenu 已有值要原样保留")
    }

    func testEnableKeepsEntryThatCarriesKeyEquivalent() {
        let status: [String: Any] = [termA: ["key_equivalent": "@$T",
                                             "enabled_context_menu": false,
                                             "presentation_modes": ["ContextMenu": false, "ServicesMenu": false]]]
        let out = enableTermA(status, unique: true)
        let entry = out[termA] as? [String: Any]
        XCTAssertNotNil(entry, "有 key_equivalent 的条目 enable 后必须保留，不能整键删除")
        XCTAssertEqual(entry?["key_equivalent"] as? String, "@$T")
        XCTAssertEqual(entry?["enabled_context_menu"] as? Bool, true)
        XCTAssertEqual((entry?["presentation_modes"] as? [String: Any])?["ContextMenu"] as? Bool, true)
    }

    func testEnableKeepsEntryWhenServicesMenuExplicitlyDisabled() {
        // enabled_services_menu == false 是服务菜单维度的独立状态，enable 上下文菜单不能抹掉它
        let status: [String: Any] = [termA: ["enabled_context_menu": false,
                                             "enabled_services_menu": false,
                                             "presentation_modes": ["ContextMenu": false, "ServicesMenu": false]]]
        let out = enableTermA(status, unique: true)
        let entry = out[termA] as? [String: Any]
        XCTAssertNotNil(entry, "enabled_services_menu=false 属于需保留的状态")
        XCTAssertEqual(entry?["enabled_context_menu"] as? Bool, true)
        XCTAssertEqual(entry?["enabled_services_menu"] as? Bool, false)
        XCTAssertFalse(termADisabled(out, unique: true))
    }

    // MARK: - 本地化标题

    func testLocalizedTitleExactKeyMatched() {
        let locKey = "com.apple.Terminal - “文件夹”新建终端 - newTerminalAtFolder"
        let status: [String: Any] = [locKey: bareDisabled]
        let disabled = ServiceStatusEditor.isDisabled(in: status, bundleID: "com.apple.Terminal",
                                                      menuTitle: "New Terminal at Folder",
                                                      localizedTitle: "“文件夹”新建终端",
                                                      message: "newTerminalAtFolder", isPairUnique: false)
        XCTAssertTrue(disabled, "本地化标题的精确键应被命中（即便 pair 非唯一）")

        let enabled = ServiceStatusEditor.apply(enabled: true, to: status, bundleID: "com.apple.Terminal",
                                                menuTitle: "New Terminal at Folder",
                                                localizedTitle: "“文件夹”新建终端",
                                                message: "newTerminalAtFolder", isPairUnique: false)
        XCTAssertNil(enabled[locKey], "命中的本地化键应被就地处理（无其他状态则删除）")
        XCTAssertNil(enabled[termA], "不应顺手合成 default 标题键")
    }

    func testNonUniqueSynthesizeDoubleWritesLocalizedKey() {
        // pair 非唯一时无模糊兜底，合成禁用条目双写 default + 本地化两个精确键以最大化系统命中
        let locKey = "com.apple.Terminal - “文件夹”新建终端 - newTerminalAtFolder"
        let out = ServiceStatusEditor.apply(enabled: false, to: [:], bundleID: "com.apple.Terminal",
                                            menuTitle: "New Terminal at Folder",
                                            localizedTitle: "“文件夹”新建终端",
                                            message: "newTerminalAtFolder", isPairUnique: false)
        XCTAssertEqual((out[termA] as? [String: Any])?["enabled_context_menu"] as? Bool, false)
        XCTAssertEqual((out[locKey] as? [String: Any])?["enabled_context_menu"] as? Bool, false)
        XCTAssertNil(out[termB], "双写仅限本服务的标题变体，不得波及兄弟键")
    }

    // MARK: - 模糊匹配仅在唯一时启用

    func testFuzzyFallbackOnlyWhenPairUnique() {
        // 第三种标题变体（既非 default 也非已知本地化），只有唯一 pair 才允许前后缀兜底
        let weirdKey = "com.apple.Terminal - Neues Terminal im Ordner - newTerminalAtFolder"
        let status: [String: Any] = [weirdKey: bareDisabled]

        XCTAssertTrue(termADisabled(status, unique: true), "唯一 pair：模糊兜底应命中未知标题变体")
        XCTAssertFalse(termADisabled(status, unique: false), "非唯一 pair：严禁模糊匹配")

        // 唯一 pair 时禁用应就地改值，而不是另起新键
        let out = disableTermA(status, unique: true)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual((out[weirdKey] as? [String: Any])?["enabled_context_menu"] as? Bool, false)
        XCTAssertNil(out[termA])
    }

    func testFuzzyDoesNotMatchDegenerateShortKey() {
        // "(null) - runWorkflowAsService" 同时满足 hasPrefix/hasSuffix（前后缀重叠），不得误命中
        let degenerate = "(null) - runWorkflowAsService"
        let status: [String: Any] = [degenerate: bareDisabled]
        XCTAssertFalse(ServiceStatusEditor.isDisabled(in: status, bundleID: nil,
                                                      menuTitle: "Resize Images", localizedTitle: nil,
                                                      message: "runWorkflowAsService", isPairUnique: true))
    }

    // MARK: - 无关键 pass-through

    func testUnrelatedKeysPassThroughBothOperations() {
        let unrelated: [String: Any] = [
            "com.apple.Stickies - Make Sticky - makeSticky":
                ["enabled_context_menu": false, "key_equivalent": "@Y",
                 "presentation_modes": ["ContextMenu": false, "ServicesMenu": true]],
            "NSServicesStatusGarbage": 42,   // 非字典值也要原样幸存
            "com.apple.Terminal - New Terminal at Folder - somethingElse": bareDisabled,  // message 不同
        ]
        var status = unrelated
        status[termB] = bareDisabled

        let afterDisable = disableTermA(status, unique: false)
        let afterEnable = enableTermA(afterDisable, unique: false)
        for (key, value) in unrelated {
            XCTAssertEqual(afterDisable[key] as? NSObject, value as? NSObject, "disable 后 \(key) 应原样保留")
            XCTAssertEqual(afterEnable[key] as? NSObject, value as? NSObject, "enable 后 \(key) 应原样保留")
        }
        XCTAssertEqual(afterEnable[termB] as? NSDictionary, bareDisabled as NSDictionary)
        XCTAssertNil(afterEnable[termA])
    }
}
