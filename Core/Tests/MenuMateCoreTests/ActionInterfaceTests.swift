import XCTest
import WebKit
@testable import MenuMateCore

final class ActionInterfaceTests: XCTestCase {
    @MainActor
    func testLocalPageRulesCompileInWebKit() async throws {
        let store = WKContentRuleListStore.default()!
        let identifier = "MenuMateRulesTest-" + UUID().uuidString
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier,
                                         encodedContentRuleList: ActionInterface.localContentRules) { list, error in
                if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: error ?? CocoaError(.coderInvalidValue)) }
            }
        }
        XCTAssertEqual(list.identifier, identifier)
        try await store.removeContentRuleList(forIdentifier: identifier)
    }

    func testLegacyActionStillDecodesWithoutInterface() throws {
        let action = MenuConfig.defaultSeed().actions[0]
        let encoded = try JSONEncoder().encode(action)
        XCTAssertNil(try JSONDecoder().decode(MenuAction.self, from: encoded).interface)
    }
    func testInterfaceRoundTripAndDefaultSize() throws {
        let spec = try JSONDecoder().decode(ActionInterface.self, from: Data(#"{"entry":"ui/index.html"}"#.utf8))
        XCTAssertEqual(spec.width, 500)
        var action = MenuConfig.defaultSeed().actions[0]
        action.interface = spec
        XCTAssertEqual(try JSONDecoder().decode(MenuAction.self, from: JSONEncoder().encode(action)).interface, spec)
    }
    func testManifestRejectsRemoteAndEscapingInterfacePaths() throws {
        for path in ["/tmp/ui.html", "../ui.html", "ui/../../ui.html", "https://example.com/index.html"] {
            let manifest = PackManifest(schemaVersion: 2, name: "Test", actions: [
                PackAction(id: "a", title: "A", script: "a.zsh", interface: ActionInterface(entry: path))])
            XCTAssertThrowsError(try manifest.validate())
        }
        let manifest = PackManifest(schemaVersion: 2, name: "Test", actions: [
            PackAction(id: "a", title: "A", script: "a.zsh", interface: ActionInterface(entry: "ui/index.html"))])
        XCTAssertNoThrow(try manifest.validate())
        XCTAssertEqual(try PackManifest.decode(JSONEncoder().encode(manifest)).actions[0].interface?.entry, "ui/index.html")
        var older = manifest
        older.schemaVersion = 1
        XCTAssertThrowsError(try older.validate())
    }
    func testParametersAreBoundedJSONObjectsAndKeepLiteralShellCharacters() throws {
        let text = #"$(touch /tmp/should-not-exist); echo "'\n"#
        let json = try ActionParameters.encode(["name": text, "quality": 80, "remember": true])
        XCTAssertEqual(try ActionParameters.decode(json)["name"] as? String, text)
        XCTAssertThrowsError(try ActionParameters.encode(["not", "an", "object"]))
        XCTAssertThrowsError(try ActionParameters.encode(["large": String(repeating: "a", count: 70000)]))
        XCTAssertThrowsError(try ActionParameters.decode("[]"))
    }
    func testInvalidTimeoutCannotCrashScriptExecution() {
        let result = ShellRunner.runScript(ScriptSpec(inlineSource: "true", timeoutSeconds: -1),
                                           paths: [], variant: nil, scriptBase: URL(fileURLWithPath: "/tmp"), cwd: nil)
        XCTAssertEqual(result.exitCode, -1)
    }
    func testInteractiveMenuUsesEllipsisAndStillDispatchesTheSameAction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var action = MenuConfig.defaultSeed().actions[0]
        action.title = "Options"
        action.matching = MatchRule(targets: .container)
        action.variants = nil
        action.isEnabled = true
        action.interface = ActionInterface(entry: "ui/index.html")
        let menu = MenuBuilder.build(MenuBuildInput(config: MenuConfig(schemaVersion: 1, actions: [action]),
                                                    context: .container(directory), heartbeatFresh: true, variantListings: [:]))
        XCTAssertEqual(menu.first?.title, "Options…")
        XCTAssertEqual(menu.first?.request?.actionID, action.id)
    }
    func testOmittedSchemaStaysLegacyAndCannotEnableHTML() throws {
        let legacy = try PackManifest.decode(Data(#"{"name":"Legacy","actions":[{"id":"a","title":"A","script":"a.zsh"}]}"#.utf8))
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertNoThrow(try legacy.validate())
        let interactive = try PackManifest.decode(Data(#"{"name":"HTML","actions":[{"id":"a","title":"A","script":"a.zsh","interface":{"entry":"index.html"}}]}"#.utf8))
        XCTAssertThrowsError(try interactive.validate()) { error in
            XCTAssertEqual(error as? PackManifest.ValidationError, .interfaceRequiresSchema2)
        }
    }

}
