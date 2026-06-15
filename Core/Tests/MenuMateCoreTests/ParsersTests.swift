import XCTest
@testable import MenuMateCore

final class ParsersTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
        return try Data(contentsOf: url)
    }

    // MARK: pluginkit

    func testParseCannedPluginkitLines() {
        let sample = """
        +    com.getdropbox.dropbox.garcon(231.4.5132)\t5DD8B056-1234-4321-ABCD-0123456789AB\t/Applications/Dropbox.app/Contents/PlugIns/garcon.appex
        -    com.tencent.xinWeChat.FinderExtension(4.0.6)\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t/Applications/WeChat.app/Contents/PlugIns/FinderExtension.appex
             com.example.unknown(1.0)\t11111111-2222-3333-4444-555555555555\t/Applications/Example.app/Contents/PlugIns/X.appex
        """
        let parsed = PluginkitParser.parse(sample)
        XCTAssertEqual(parsed.count, 3)
        XCTAssertEqual(parsed[0].election, .use)
        XCTAssertEqual(parsed[0].bundleID, "com.getdropbox.dropbox.garcon")
        XCTAssertEqual(parsed[0].version, "231.4.5132")
        XCTAssertEqual(parsed[0].path, "/Applications/Dropbox.app/Contents/PlugIns/garcon.appex")
        XCTAssertEqual(parsed[1].election, .ignore)
        XCTAssertEqual(parsed[2].election, .unknown)
    }

    func testParseRealPluginkitFixtureFindsOwnFormat() throws {
        let text = String(decoding: try fixture("pluginkit-findersync.txt"), as: UTF8.self)
        let parsed = PluginkitParser.parse(text)
        // 真实输出每个非空行都应能解析出合法 bundleID 和绝对路径
        // 排除 "(N plug-ins)" 这类汇总行
        let nonEmptyLines = text.split(separator: "\n").filter {
            let s = $0.trimmingCharacters(in: .whitespaces)
            return !s.isEmpty && !s.hasPrefix("(")
        }
        XCTAssertEqual(parsed.count, nonEmptyLines.count, "真实 pluginkit 输出每行都应可解析")
        XCTAssertTrue(parsed.allSatisfy { $0.path.hasPrefix("/") && $0.bundleID.contains(".") })
    }

    // MARK: pbs key

    func testStatusKeyFormats() {
        XCTAssertEqual(PbsKey.statusKey(bundleID: "com.apple.Stickies", menuTitle: "制作便笺", message: "makeSticky"),
                       "com.apple.Stickies - 制作便笺 - makeSticky")
        XCTAssertEqual(PbsKey.statusKey(bundleID: nil, menuTitle: "转换图像", message: "runWorkflowAsService"),
                       "(null) - 转换图像 - runWorkflowAsService")
    }

    func testDisabledStatusValueShape() {
        let v = PbsKey.disabledStatusValue() as NSDictionary
        XCTAssertEqual(v["enabled_context_menu"] as? Bool, false)
        XCTAssertEqual(v["enabled_services_menu"] as? Bool, false)
        XCTAssertEqual((v["presentation_modes"] as? NSDictionary)?["ContextMenu"] as? Bool, false)
    }

    // MARK: services cache

    func testParseRealServicesCache() throws {
        let items = try ServicesCacheParser.parse(plistData: try fixture("services-cache.plist"))
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { !$0.menuTitle.isEmpty && !$0.message.isEmpty })
    }

    // MARK: pluginkit — additional regression cases

    func testParseCanned4FieldFormatWithTimestamp() {
        let line = "+    com.example.ext(2.0)\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t2026-06-11 03:46:54 +0000\t/Applications/Example.app/Contents/PlugIns/E.appex"
        let parsed = PluginkitParser.parse(line)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].version, "2.0")
        XCTAssertEqual(parsed[0].path, "/Applications/Example.app/Contents/PlugIns/E.appex")
    }

    func testParenthesesInVersionAndBundleParsing() {
        let line = "+    com.weird.app(1.2 (345))\tAAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\t/Applications/W.app/Contents/PlugIns/W.appex"
        let parsed = PluginkitParser.parse(line)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].bundleID, "com.weird.app")
        XCTAssertEqual(parsed[0].path, "/Applications/W.app/Contents/PlugIns/W.appex")
    }

    // MARK: services cache — additional regression cases

    func testParseFlatRootServicesCacheFallback() throws {
        let plist: [String: Any] = ["CFVendedServices": [[
            "NSMenuItem": ["default": "Flat Service"],
            "NSMessage": "flatMessage",
        ]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let items = try ServicesCacheParser.parse(plistData: data)
        XCTAssertEqual(items.first?.menuTitle, "Flat Service")
    }

    func testNonMenuServicesFlaggedNotDropped() throws {
        let plist: [String: Any] = ["NSServices": ["CFVendedServices": [[
            "NSMenuItem": [String: Any](),
            "NSMessage": "checkSpelling",
            "NSBundleIdentifier": "com.apple.AppleSpell",
        ]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let items = try ServicesCacheParser.parse(plistData: data)
        XCTAssertEqual(items.first?.hasMenuItem, false)
    }

    func testRealServicesCacheHasAtLeastOneLocalizedTitle() throws {
        let items = try ServicesCacheParser.parse(plistData: try fixture("services-cache.plist"))
        XCTAssertTrue(items.contains { $0.localizedTitle != nil && !$0.localizedTitle!.isEmpty },
                      "services-cache.plist (CFPrincipalLocalizations=[zh-Hans]) should yield at least one localizedTitle")
    }

    // MARK: workflow Info.plist

    func testParseWorkflowInfoPlist() throws {
        let plist: [String: Any] = ["NSServices": [[
            "NSMenuItem": ["default": "我的快捷操作"],
            "NSMessage": "runWorkflowAsService",
            "NSSendFileTypes": ["public.image"],
        ]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let wf = try WorkflowParser.parse(infoPlistData: data)
        XCTAssertEqual(wf?.menuTitle, "我的快捷操作")
        XCTAssertEqual(wf?.message, "runWorkflowAsService")
        XCTAssertEqual(wf?.sendFileTypes, ["public.image"])
    }
}
