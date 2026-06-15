import XCTest
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

    // 混合 UTI(图片 + 非图片)在普通文件下仍显示(非专属图片)。
    func testMixedUTINotExclusive() {
        let rule = MatchRule(targets: .files, utis: ["public.image", "public.movie"])
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .file))
    }

    // 非图片专属 UTI(如视频)在图片模拟对象下不显示。
    func testNonImageUTIHiddenForImage() {
        let rule = MatchRule(targets: .files, utis: ["public.movie"])
        XCTAssertFalse(MenuPreviewVisibility.isVisible(rule, in: .image))
        XCTAssertTrue(MenuPreviewVisibility.isVisible(rule, in: .file))
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
}
