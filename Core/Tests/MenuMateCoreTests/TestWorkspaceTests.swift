import XCTest
import ImageIO
import CoreGraphics
import AVFoundation
@testable import MenuMateCore

final class TestWorkspaceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func action(_ rule: MatchRule, preset: String? = nil) -> MenuAction {
        MenuAction(id: UUID(), title: "Test", icon: .symbol("bolt"), kind: .runScript(ScriptSpec(inlineSource: "true")),
                   matching: rule, placement: .topLevel, presetKey: preset, isEnabled: false, sortOrder: 0)
    }

    func testImagesAreDecodableAndSelectionCountsMatch() throws {
        for resource in [TestResource.jpeg, .png, .tiff, .gif] {
            let a = action(MatchRule(targets: .files, utis: [resource.type.identifier], minSelectionCount: 2))
            let workspace = try TestWorkspace.create(action: a, resource: resource, count: 2, baseDirectory: root)
            XCTAssertEqual(workspace.inputs.count, 2)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(workspace.inputs[0] as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 800)
            XCTAssertTrue(RuleMatcher.matches(rule: a.matching, context: .items(workspace.inputs)))
            XCTAssertTrue(workspace.inputs.allSatisfy { $0.path.hasPrefix(workspace.directory.path + "/") })
        }
    }
    func testPDFArchiveAudioAndVideoContainUsableResources() throws {
        let a = action(MatchRule(targets: .files))
        for resource in [TestResource.pdf, .archive, .audio, .video] {
            let workspace = try TestWorkspace.create(action: a, resource: resource, count: 1, baseDirectory: root)
            let url = workspace.inputs[0]
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 40)
            switch resource {
            case .pdf: XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 1)
            case .archive: XCTAssertEqual(ShellRunner.run("/usr/bin/unzip", ["-t", url.path], timeout: 5).exitCode, 0)
            case .audio: XCTAssertEqual(String(decoding: try Data(contentsOf: url).prefix(4), as: UTF8.self), "RIFF")
            case .video: XCTAssertFalse(AVURLAsset(url: url).tracks(withMediaType: .video).isEmpty)
            default: break
            }
        }
    }
    func testDirectoriesAndApplicationBundlesMatchTheirActualType() throws {
        for resource in [TestResource.folder, .application] {
            let rule = MatchRule(targets: resource == .folder ? .folders : .files, utis: [resource.type.identifier])
            let workspace = try TestWorkspace.create(action: action(rule), resource: resource, count: 1, baseDirectory: root)
            XCTAssertTrue(RuleMatcher.matches(rule: rule, context: .items(workspace.inputs)))
        }
    }
    func testEachRunHasIndependentDataAndTemplates() throws {
        let first = try TestWorkspace.create(action: action(MatchRule(targets: .container), preset: "paste"),
                                             resource: .folder, count: 1, baseDirectory: root)
        let second = try TestWorkspace.create(action: action(MatchRule(targets: .container)),
                                              resource: .folder, count: 1, baseDirectory: root)
        XCTAssertNotEqual(first.directory, second.directory)
        XCTAssertFalse(TemplateStore.list(in: first.templatesDirectory).isEmpty)
        let cutBuffer = try String(contentsOf: first.dataDirectory.appendingPathComponent("cutbuffer"))
        XCTAssertTrue(cutBuffer.hasPrefix(first.directory.path + "/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.dataDirectory.appendingPathComponent("cutbuffer").path))
        let result = ShellRunner.runScript(
            ScriptSpec(inlineSource: #"printf '%s' "$MENUMATE_TEST_ROOT" > "$MENUMATE_DATA/result.txt""#),
            paths: first.inputs.map(\.path), variant: nil, scriptBase: root,
            cwd: first.workingDirectory, extraEnv: first.environment)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(try String(contentsOf: first.dataDirectory.appendingPathComponent("result.txt")), first.directory.path)
    }
    func testUnsupportedTypesAndUnsatisfiedCountsFailInsteadOfCreatingFakeFiles() throws {
        let unknown = action(MatchRule(targets: .files, utis: ["com.example.unknown-format"]))
        XCTAssertTrue(TestResource.matching(unknown.matching).isEmpty)
        XCTAssertThrowsError(try TestWorkspace.create(action: unknown, resource: .text, count: 1, baseDirectory: root))
        let multiple = action(MatchRule(targets: .files, minSelectionCount: 2))
        XCTAssertThrowsError(try TestWorkspace.create(action: multiple, resource: .text, count: 1, baseDirectory: root))
        XCTAssertThrowsError(try TestWorkspace.create(action: multiple, resource: .text, count: 21, baseDirectory: root))
        let directories = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("TestRuns"), includingPropertiesForKeys: nil)
        XCTAssertTrue(directories.isEmpty)
    }

    func testBundledCompressionProducesCopiesWithoutOverwritingOrUpscaling() throws {
        let workspace = try TestWorkspace.create(action: action(MatchRule(targets: .files, utis: ["public.jpeg"])),
                                                 resource: .jpeg, count: 1, baseDirectory: root)
        let original = workspace.inputs[0]
        let before = try Data(contentsOf: original)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let spec = ScriptSpec(scriptPath: repository.appendingPathComponent("App/ActionExamples/image-compress.zsh").path)
        var environment = workspace.environment
        environment["MENUMATE_LOCALE"] = "zh-Hans"
        environment["MENUMATE_INPUT"] = try ActionParameters.encode(["quality": 80, "maxEdge": 128, "output": "same"])
        for _ in 0..<2 {
            let result = ShellRunner.runScript(spec, paths: [original.path], variant: nil,
                                               scriptBase: repository, cwd: workspace.workingDirectory, extraEnv: environment)
            XCTAssertEqual(result.exitCode, 0, result.stderr)
        }
        let first = workspace.workingDirectory.appendingPathComponent("Sample-1-压缩.jpg")
        let second = workspace.workingDirectory.appendingPathComponent("Sample-1-压缩 2.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let image = try XCTUnwrap(CGImageSourceCreateWithURL(first as CFURL, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(image, 0, nil)?.width, 128)
        XCTAssertEqual(try Data(contentsOf: original), before)
        environment["MENUMATE_INPUT"] = try ActionParameters.encode(["quality": 80, "maxEdge": 1920, "output": "subfolder"])
        let result = ShellRunner.runScript(spec, paths: [original.path], variant: nil,
                                           scriptBase: repository, cwd: workspace.workingDirectory, extraEnv: environment)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let unchangedSize = workspace.workingDirectory.appendingPathComponent("压缩图片/Sample-1-压缩.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(unchangedSize as CFURL, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width, 800)
        environment["MENUMATE_LOCALE"] = "en"
        let english = ShellRunner.runScript(spec, paths: [original.path], variant: nil,
                                            scriptBase: repository, cwd: workspace.workingDirectory, extraEnv: environment)
        XCTAssertEqual(english.exitCode, 0, english.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.workingDirectory.appendingPathComponent("Compressed Images/Sample-1-compressed.jpg").path))
    }
    func testCustomVariantDirectoryIsRejectedBeforeCreatingSamples() throws {
        var a = action(MatchRule(targets: .container))
        a.variants = .directoryListing("CustomTemplates")
        XCTAssertThrowsError(try TestWorkspace.create(action: a, resource: .folder, count: 1, baseDirectory: root)) { error in
            guard case TestWorkspace.Failure.unsupportedVariantDirectory = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("TestRuns").path))
        for path in ["Templates", "./Templates/", root.appendingPathComponent("Templates").path] {
            a.variants = .directoryListing(path)
            let workspace = try TestWorkspace.create(action: a, resource: .folder, count: 1, baseDirectory: root)
            XCTAssertEqual(try workspace.variants(for: a), ["Markdown.md", "Text.txt"])
        }
    }

}
