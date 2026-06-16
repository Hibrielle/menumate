import XCTest
@testable import MenuMateCore

final class MenuBuilderTests: XCTestCase {
    private var dir: URL!
    private var file: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("a.png")
        FileManager.default.createFile(atPath: file.path, contents: Data())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func input(config: MenuConfig, context: MatchContext,
                       listings: [UUID: [String]] = [:], fresh: Bool = true) -> MenuBuildInput {
        MenuBuildInput(config: config, context: context, heartbeatFresh: fresh,
                       variantListings: listings)
    }

    func testStaleHeartbeatYieldsEmpty() {
        let specs = MenuBuilder.build(input(config: .defaultSeed(), context: .items([file]), fresh: false))
        XCTAssertTrue(specs.isEmpty)
    }

    // 注:预设标题已本地化(随语言),测试改用 presetKey 推导期望标题,与具体语言无关。
    private func title(_ seed: MenuConfig, _ presetKey: String) -> String {
        seed.actions.first { $0.presetKey == presetKey }!.title
    }

    // 自建固定变体动作:测的是 MenuBuilder 的 .fixed 展开本身,不依赖某条具体出厂预设
    // (内置预设已精简,不再含固定变体的「图片转换」——它已挪到 Image 扩展包)。
    private func fixedVariantConfig(_ values: [String], title: String = "Convert") -> MenuConfig {
        let action = MenuAction(
            id: UUID(), title: title, icon: .symbol("photo"),
            kind: .runScript(ScriptSpec(scriptPath: "x.sh")),
            matching: MatchRule(targets: .files), placement: .topLevel,
            variants: .fixed(values), isEnabled: true, sortOrder: 0)
        return MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: [action])
    }

    func testFixedVariantsExpandToChildren() {
        let config = fixedVariantConfig(["png", "jpeg", "heic", "tiff"])
        let specs = MenuBuilder.build(input(config: config, context: .items([file])))
        let convert = specs.first { $0.title == "Convert" }
        XCTAssertEqual(convert?.children.map(\.title), ["png", "jpeg", "heic", "tiff"])
        XCTAssertEqual(convert?.children.first?.request?.variant, "png")
        XCTAssertNil(convert?.request)   // 父节点不可点击
    }

    func testDirectoryListingVariantsUseInjectedListings() {
        let seed = MenuConfig.defaultSeed()
        let newFileID = seed.actions.first { $0.presetKey == "new-file" }!.id
        let specs = MenuBuilder.build(input(config: seed, context: .container(dir),
                                            listings: [newFileID: ["文本.txt", "Markdown.md"]]))
        let newFile = specs.first { $0.title == title(seed, "new-file") }
        XCTAssertEqual(newFile?.children.map(\.title), ["文本.txt", "Markdown.md"])
    }

    func testEmptyVariantsHidesAction() {
        let seed = MenuConfig.defaultSeed()
        // 不注入 listings → directoryListing 类动作（新建文件）应整体隐藏
        let specs = MenuBuilder.build(input(config: seed, context: .container(dir)))
        XCTAssertFalse(specs.contains { $0.title == title(seed, "new-file") })
        // 但「粘贴到此处」是普通容器动作，应在
        XCTAssertTrue(specs.contains { $0.title == title(seed, "paste") })
    }

    func testSubmenuPlacementGroupsUnderMenuMate() {
        var seed = MenuConfig.defaultSeed()
        let copyTitle = title(seed, "copy-path")
        seed.actions[0].placement = .submenu   // 复制路径挪进子菜单
        let specs = MenuBuilder.build(input(config: seed, context: .items([file])))
        let group = specs.first { $0.title == "MenuMate" }
        XCTAssertEqual(group?.children.first?.title, copyTitle)
        XCTAssertFalse(specs.contains { $0.title == copyTitle })
    }

    func testPrepareListingsResolvesRelativeAgainstBase() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let templates = base.appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: templates.appendingPathComponent("文本.txt").path, contents: Data())
        let seed = MenuConfig.defaultSeed()
        let newFileID = seed.actions.first { $0.presetKey == "new-file" }!.id
        // 无 context：快照要覆盖一切上下文，所有 enabled 的 directoryListing 动作都解析
        let listings = MenuBuilder.prepareListings(config: seed, base: base)
        XCTAssertEqual(listings[newFileID], ["文本.txt"])
    }

    func testPrepareListingsSkipsDisabledActions() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let templates = base.appendingPathComponent("Templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: templates.appendingPathComponent("文本.txt").path, contents: Data())
        var seed = MenuConfig.defaultSeed()
        let idx = try XCTUnwrap(seed.actions.firstIndex { $0.presetKey == "new-file" })
        seed.actions[idx].isEnabled = false
        let listings = MenuBuilder.prepareListings(config: seed, base: base)
        XCTAssertNil(listings[seed.actions[idx].id])
    }

    func testFixedEmptyVariantsHidesAction() {
        let config = fixedVariantConfig([])
        let specs = MenuBuilder.build(input(config: config, context: .items([file])))
        XCTAssertFalse(specs.contains { $0.title == "Convert" })
    }

    func testTemplateStoreFiltersSubdirectoriesAndCaps() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base.appendingPathComponent("subdir"), withIntermediateDirectories: true)
        for i in 0..<60 {
            FileManager.default.createFile(atPath: base.appendingPathComponent(String(format: "t%02d.txt", i)).path, contents: Data())
        }
        let list = TemplateStore.list(in: base)
        XCTAssertEqual(list.count, 50, "默认上限 50")
        XCTAssertFalse(list.contains("subdir"), "子目录不得出现")
    }
}
