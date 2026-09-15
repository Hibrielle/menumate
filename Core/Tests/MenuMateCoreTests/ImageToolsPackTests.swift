import XCTest
import ImageIO
@testable import MenuMateCore

final class ImageToolsPackTests: XCTestCase {
    private var pack: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples/image-tools-pack")
    }

    func testPackContainsTwoIndependentInteractiveActions() throws {
        let manifest = try PackManifest.decode(Data(contentsOf: pack.appendingPathComponent("manifest.json")))
        try manifest.validate()
        XCTAssertEqual(manifest.actions.map(\.id), ["compress-jpeg", "convert-image"])
        XCTAssertEqual(Set(manifest.actions.compactMap { $0.interface?.entry }).count, 2)
        for action in manifest.actions {
            XCTAssertFalse(try Data(contentsOf: pack.appendingPathComponent(action.script)).isEmpty)
            let page = try XCTUnwrap(action.interface?.entry)
            XCTAssertTrue(try String(contentsOf: pack.appendingPathComponent(page)).contains("bridge.submit"))
        }
    }

    func testConversionFormatsBatchCollisionAndOriginalPreservation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let action = MenuAction(id: UUID(), title: "Test", icon: .symbol("photo"),
            kind: .runScript(ScriptSpec(inlineSource: "true")), matching: MatchRule(targets: .files),
            placement: .topLevel, isEnabled: false, sortOrder: 0)
        let workspace = try TestWorkspace.create(action: action, resource: .png, count: 2, baseDirectory: root)
        let renamed = workspace.workingDirectory.appendingPathComponent("空 格 ' $sample.png")
        try FileManager.default.moveItem(at: workspace.inputs[0], to: renamed)
        let inputs = [renamed, workspace.inputs[1]]
        let originals = try inputs.map { try Data(contentsOf: $0) }
        let spec = ScriptSpec(scriptPath: pack.appendingPathComponent("actions/convert.zsh").path)
        var env = workspace.environment
        for (format, type) in [("png", "public.png"), ("jpeg", "public.jpeg"), ("tiff", "public.tiff")] {
            env["MENUMATE_INPUT"] = try ActionParameters.encode(["format": format, "quality": 80, "output": "same"])
            env["MENUMATE_LOCALE"] = "en"
            for _ in 0..<2 {
                let result = ShellRunner.runScript(spec, paths: inputs.map(\.path), variant: nil,
                    scriptBase: pack, cwd: workspace.workingDirectory, extraEnv: env)
                XCTAssertEqual(result.exitCode, 0, result.stderr)
                let outputs = result.stdout.split(separator: "\n").map(String.init)
                XCTAssertEqual(outputs.count, 2)
                for output in outputs {
                    let source = try XCTUnwrap(CGImageSourceCreateWithURL(URL(fileURLWithPath: output) as CFURL, nil))
                    XCTAssertEqual(CGImageSourceGetType(source) as String?, type)
                    XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width, 800)
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.workingDirectory.appendingPathComponent("空 格 ' $sample-converted 2.png").path))
        XCTAssertEqual(try inputs.map { try Data(contentsOf: $0) }, originals)
        env["MENUMATE_INPUT"] = try ActionParameters.encode(["format": "jpeg", "quality": 80, "output": "subfolder"])
        env["MENUMATE_LOCALE"] = "zh-Hans"
        let localized = ShellRunner.runScript(spec, paths: [renamed.path], variant: nil,
            scriptBase: pack, cwd: workspace.workingDirectory, extraEnv: env)
        XCTAssertEqual(localized.exitCode, 0, localized.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.workingDirectory.appendingPathComponent("转换图片/空 格 ' $sample-转换.jpg").path))
        env["MENUMATE_INPUT"] = try ActionParameters.encode(["format": "png; touch bad", "quality": 80, "output": "same"])
        let invalid = ShellRunner.runScript(spec, paths: [renamed.path], variant: nil,
            scriptBase: pack, cwd: workspace.workingDirectory, extraEnv: env)
        XCTAssertEqual(invalid.exitCode, 2)
    }

    func testPackCompressionExecutesItsOwnScript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let action = MenuAction(id: UUID(), title: "Test", icon: .symbol("photo"),
            kind: .runScript(ScriptSpec(inlineSource: "true")), matching: MatchRule(targets: .files),
            placement: .topLevel, isEnabled: false, sortOrder: 0)
        let workspace = try TestWorkspace.create(action: action, resource: .jpeg, count: 1, baseDirectory: root)
        var env = workspace.environment
        env["MENUMATE_INPUT"] = try ActionParameters.encode(["quality": 70, "maxEdge": 128, "output": "same"])
        env["MENUMATE_LOCALE"] = "en"
        let result = ShellRunner.runScript(ScriptSpec(scriptPath: pack.appendingPathComponent("actions/compress.zsh").path),
            paths: workspace.inputs.map(\.path), variant: nil, scriptBase: pack, cwd: workspace.workingDirectory, extraEnv: env)
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let output = workspace.workingDirectory.appendingPathComponent("Sample-1-compressed.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width, 128)
    }
}
