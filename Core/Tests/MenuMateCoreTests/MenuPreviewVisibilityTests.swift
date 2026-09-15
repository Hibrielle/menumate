import XCTest
import UniformTypeIdentifiers
@testable import MenuMateCore

final class MenuPreviewVisibilityTests: XCTestCase {

    // targets=.any 无 UTI：除空白处外都显示（empty 仅 container）。
    func testAnyNoUTI() {
        let rule = MatchRule(targets: .any)
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .file))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .folder))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .empty))
    }

    // targets=.files 限定 public.image：图片显示，普通文件不显示，文件夹/空白不显示。
    func testFilesImageExclusive() {
        let rule = MatchRule(targets: .files, utis: ["public.image"])
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .file))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .folder))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .empty))
    }

    // targets=.files 无 UTI:图片与普通文件都显示,文件夹不显示。
    func testFilesNoUTI() {
        let rule = MatchRule(targets: .files)
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .file))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .folder))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .empty))
    }

    // targets=.folders:仅文件夹显示。
    func testFoldersOnly() {
        let rule = MatchRule(targets: .folders)
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .file))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .folder))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .empty))
    }

    // targets=.container:仅空白处显示。
    func testContainerOnly() {
        let rule = MatchRule(targets: .container)
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .file))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .folder))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .empty))
    }

    // “文件”的默认示例是 TXT，不再代表所有非图片类型的并集。
    func testMixedUTIDoesNotMatchPlainTextExample() {
        let rule = MatchRule(targets: .files, utis: ["public.image", "public.movie"])
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .file))
    }

    // 非图片专属 UTI(如视频)在图片模拟对象下不显示。
    func testNonImageUTIHiddenForImage() {
        let rule = MatchRule(targets: .files, utis: ["public.movie"])
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .file))
        let movie = MenuPreviewVisibility.context(for: .file, contentType: .mpeg4Movie)
        XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: movie), .matched)
    }

    // MenuAction 便捷重载。
    func testActionOverload() {
        let action = MenuAction(id: UUID(), title: "t", icon: .symbol("s"),
                                kind: .runScript(ScriptSpec(inlineSource: "true")),
                                matching: MatchRule(targets: .container),
                                placement: .topLevel, isEnabled: true, sortOrder: 0)
        XCTAssertTrue(MenuPreviewVisibility.isVisible(action, in: .empty))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(action, in: .file))
    }

    func testDefaultExamplesHaveConcreteTypes() {
        XCTAssertEqual(MenuPreviewVisibility.context(for: .image), .items([MatchItem(isDirectory: false, contentType: .png)]))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .file), .items([MatchItem(isDirectory: false, contentType: .plainText)]))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .folder), .items([MatchItem(isDirectory: true, contentType: .folder)]))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .folder, contentType: .png), MenuPreviewVisibility.context(for: .folder))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .empty, selectionCount: 3), .container)
    }

    func testParentTypeAndFolderRejectionUseSharedRules() {
        XCTAssertTrue(MenuPreviewVisibility.isVisible(MatchRule(targets: .files, utis: ["public.data"]), in: .image))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(MatchRule(targets: .any, utis: ["public.image"]), in: .folder))
    }

    func testExplicitApplicationExampleIsAFile() {
        let application = MenuPreviewVisibility.context(for: .file, contentType: .applicationBundle)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .files, utis: ["com.apple.application"]), context: application), .matched)
        XCTAssertEqual(RuleMatcher.evaluate(rule: MatchRule(targets: .folders), context: application), .targetMismatch)
    }

    func testSelectionCountChangesVisibility() {
        let rule = MatchRule(targets: .files, utis: ["public.image"], maxSelectionCount: 2, minSelectionCount: 2)
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image, selectionCount: 1))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image, selectionCount: 2))
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image, selectionCount: 3))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .image, selectionCount: 0), .items([]))
        XCTAssertEqual(MenuPreviewVisibility.context(for: .image, selectionCount: -1), .items([]))
    }

    func testDisabledActionRemainsManageableInPreview() {
        let action = MenuAction(id: UUID(), title: "Disabled", icon: .symbol("photo"),
                                kind: .runScript(ScriptSpec()), matching: MatchRule(targets: .files),
                                placement: .topLevel, isEnabled: false, sortOrder: 0)
        XCTAssertTrue(MenuPreviewVisibility.isVisible(action, in: .image))
    }

    func testRealSelectionsAndEquivalentPreviewsHaveIdenticalResults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("image.png")
        let text = directory.appendingPathComponent("document.txt")
        try Data().write(to: png)
        try Data("example".utf8).write(to: text)
        let pairs: [(MatchContext, ResolvedMatchContext)] = [
            (.items([png]), MenuPreviewVisibility.context(for: .image)),
            (.items([png, png]), MenuPreviewVisibility.context(for: .image, selectionCount: 2)),
            (.items([text]), MenuPreviewVisibility.context(for: .file)),
            (.items([directory]), MenuPreviewVisibility.context(for: .folder)),
            (.container(directory), MenuPreviewVisibility.context(for: .empty))
        ]
        let rules = [MatchRule(), MatchRule(targets: .files, utis: ["public.image"]),
                     MatchRule(targets: .files, utis: ["public.data"]), MatchRule(targets: .files, utis: ["public.text"]),
                     MatchRule(targets: .folders), MatchRule(targets: .any, utis: ["public.image"]),
                     MatchRule(targets: .files, maxSelectionCount: 1), MatchRule(targets: .files, minSelectionCount: 2),
                     MatchRule(targets: .container)]
        for (real, preview) in pairs {
            let resolved = RuleMatcher.resolve(context: real)
            for rule in rules {
                XCTAssertEqual(RuleMatcher.evaluate(rule: rule, context: resolved), RuleMatcher.evaluate(rule: rule, context: preview))
                XCTAssertEqual(RuleMatcher.matches(rule: rule, context: real), RuleMatcher.evaluate(rule: rule, context: preview) == .matched)
            }
        }
    }
}
