import XCTest
import UniformTypeIdentifiers
@testable import MenuMateCore

final class RuleMatcherTests: XCTestCase {
    private var dir: URL!
    private var file: URL!   // a.png
    private var folder: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("a.png")
        FileManager.default.createFile(atPath: file.path, contents: Data())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func action(_ rule: MatchRule, enabled: Bool = true) -> MenuAction {
        MenuAction(id: UUID(), title: "t", icon: .symbol("s"),
                   kind: .runScript(ScriptSpec(inlineSource: "true")),
                   matching: rule, placement: .topLevel, isEnabled: enabled, sortOrder: 0)
    }

    func testContainerRuleOnlyMatchesContainerContext() {
        let rule = MatchRule(targets: .container)
        XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .container(dir)))
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file])))
    }

    func testFilesRuleRejectsFolder() {
        let rule = MatchRule(targets: .files)
        XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items([file])))
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file, folder])))
    }

    func testUTIFilter() {
        let imageRule = MatchRule(targets: .files, utis: ["public.image"])
        XCTAssertTrue(RuleMatcher.matches(rule: imageRule, context: .items([file])))
        let movieRule = MatchRule(targets: .files, utis: ["public.movie"])
        XCTAssertFalse(RuleMatcher.matches(rule: movieRule, context: .items([file])))
    }

    func testMaxSelectionCount() {
        let rule = MatchRule(targets: .any, maxSelectionCount: 1)
        XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items([file])))
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file, folder])))
    }

    func testMinSelectionCount() {
        // 仅多选：选 1 个隐藏，≥2 个出现
        let rule = MatchRule(targets: .any, minSelectionCount: 2)
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file])))
        XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items([file, folder])))
    }

    func testMinAndMaxSelectionCountFormRange() {
        // 恰好 2 个：min=2 且 max=2
        let rule = MatchRule(targets: .any, maxSelectionCount: 2, minSelectionCount: 2)
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file])))
        XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items([file, folder])))
        XCTAssertFalse(RuleMatcher.matches(rule: rule, context: .items([file, folder, dir])))
    }

    func testVisibleActionsFiltersDisabledAndSorts() {
        let a = action(MatchRule(), enabled: true)
        let b = action(MatchRule(), enabled: false)
        var c = action(MatchRule(), enabled: true)
        c.sortOrder = -1
        let config = MenuConfig(schemaVersion: 1, actions: [a, b, c])
        let visible = RuleMatcher.visibleActions(in: config, context: .items([file]))
        XCTAssertEqual(visible.map(\.id), [c.id, a.id])
    }

    func testFoldersRuleAcceptsFolder() {
        XCTAssertTrue(RuleMatcher.matches(rule: MatchRule(targets: .folders), context: .items([folder])))
    }

    func testAnyRuleAcceptsMixedSelection() {
        XCTAssertTrue(RuleMatcher.matches(rule: MatchRule(targets: .any), context: .items([file, folder])))
    }

    func testVisibleActionsInContainerContextKeepsOnlyContainerRules() {
        let containerAction = action(MatchRule(targets: .container))
        let fileAction = action(MatchRule(targets: .files))
        let config = MenuConfig(schemaVersion: 1, actions: [containerAction, fileAction])
        let visible = RuleMatcher.visibleActions(in: config, context: .container(dir))
        XCTAssertEqual(visible.map(\.id), [containerAction.id])
    }

    func testResolvedImageTypesMatchTheirParents() throws {
        let jpeg = dir.appendingPathComponent("photo.jpg")
        try Data().write(to: jpeg)
        let resolved = RuleMatcher.resolve(context: .items([file, jpeg]))
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files, utis: ["public.image"]), context: resolved), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files, utis: ["public.data"]), context: resolved), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files, utis: ["public.movie"]), context: resolved), .typeMismatch)
    }

    func testApplicationPackageIsAFileWithApplicationType() throws {
        let application = dir.appendingPathComponent("Example.app")
        let contents = application.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "com.menumate.test.fixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))

        let resolved = RuleMatcher.resolve(context: .items([application]))
        guard case .items(let items) = resolved, let item = items.first else {
            return XCTFail("Expected one resolved application item")
        }
        XCTAssertTrue(item.isAvailable)
        XCTAssertFalse(item.isDirectory)
        XCTAssertTrue(item.contentType?.conforms(to: .application) == true)
        for targets in [TargetKind.any, .files] {
            XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: targets, utis: ["com.apple.application"]), context: resolved), .matched)
        }
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .folders), context: resolved), .targetMismatch)
        XCTAssertFalse(RuleMatcher.matches(rule: MatchRule(targets: .container), context: .container(application)))
    }

    func testFolderStillHasToMatchAllowedTypes() {
        let resolved = RuleMatcher.resolve(context: .items([folder]))
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .any, utis: ["public.image"]), context: resolved), .typeMismatch)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .folders, utis: ["public.folder"]), context: resolved), .matched)
    }

    func testMissingItemsFailClosedEvenWithoutTypeRestriction() {
        let missing = dir.appendingPathComponent("missing.png")
        for urls in [[missing], [file!, missing]] {
            let resolved = RuleMatcher.resolve(context: .items(urls))
            XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(), context: resolved), .unavailableItem)
            XCTAssertFalse(RuleMatcher.matches(rule: MatchRule(targets: .files), context: .items(urls)))
        }
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .container),
                                            context: RuleMatcher.resolve(context: .container(missing))), .unavailableItem)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(),
                                            context: RuleMatcher.resolve(context: .container(file))), .unavailableItem)
    }

    func testResolvedUnknownTypeCanMatchOnlyUnrestrictedRule() {
        let resolved = ResolvedMatchContext.items([MatchItem(isDirectory: false, contentType: nil)])
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files), context: resolved), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files, utis: ["public.image"]), context: resolved), .typeMismatch)
    }

    func testResolvingAgainDiscardsCachedMetadataForRemovedFile() throws {
        let selectedURL = file!
        _ = try selectedURL.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
        XCTAssertTrue(RuleMatcher.matches(rule: MatchRule(), context: .items([selectedURL])))
        try FileManager.default.removeItem(at: selectedURL)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(),
                                            context: RuleMatcher.resolve(context: .items([selectedURL]))), .unavailableItem)
    }

    func testEmptyAndSelectionCountResultsExplainRejections() {
        let image = MatchItem(isDirectory: false, contentType: .png)
        let rule = MatchRule(targets: .files, utis: ["public.image"], maxSelectionCount: 2, minSelectionCount: 2)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: .items([])), .emptySelection)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: .items([image])), .tooFew(2))
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: .items([image, image])), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: .items([image, image, image])), .tooMany(2))
    }

    func testMixedSelectionRequiresEveryItemToMatch() throws {
        let jpeg = dir.appendingPathComponent("photo.jpg")
        let pdf = dir.appendingPathComponent("document.pdf")
        try Data().write(to: jpeg)
        try Data().write(to: pdf)
        let rule = MatchRule(targets: .files, utis: ["public.image"], minSelectionCount: 2)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: RuleMatcher.resolve(context: .items([jpeg, file]))), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: RuleMatcher.resolve(context: .items([jpeg, pdf]))), .typeMismatch)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: RuleMatcher.resolve(context: .items([jpeg, folder]))), .targetMismatch)
        let acceptsBoth = MatchRule(targets: .files, utis: ["public.image", "com.adobe.pdf"])
        XCTAssertEqual(RuleMatcher.evaluate(rule: acceptsBoth, context: RuleMatcher.resolve(context: .items([jpeg, pdf]))), .matched)
    }

    func testContainerIgnoresSelectionOnlyConstraints() {
        let rule = MatchRule(targets: .container, utis: ["public.image"], maxSelectionCount: 1, minSelectionCount: 2)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: .container), .matched)
    }
    func testSymlinksMatchTheirTargetsAndBrokenLinksAreUnavailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Folder")
        let app = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("Image.png")
        try Data([1,2,3]).write(to: image)
        for (target, name, rule) in [
            (folder, "FolderLink", MatchRule(targets: .folders)),
            (image, "ImageLink", MatchRule(targets: .files, utis: ["public.image"])),
            (app, "AppLink", MatchRule(targets: .files, utis: ["com.apple.application-bundle"]))
        ] {
            let link = root.appendingPathComponent(name)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items([link])))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        }
        let broken = root.appendingPathComponent("Broken.png")
        try FileManager.default.createSymbolicLink(at: broken, withDestinationURL: root.appendingPathComponent("Missing.png"))
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(), context: RuleMatcher.resolve(context: .items([broken]))), .unavailableItem)
        XCTAssertTrue(RuleMatcher.matches(rule: MatchRule(targets: .container), context: .container(root.appendingPathComponent("FolderLink"))))
    }

}
