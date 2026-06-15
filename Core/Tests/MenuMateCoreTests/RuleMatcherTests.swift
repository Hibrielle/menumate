import XCTest
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
}
