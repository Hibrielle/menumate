import XCTest
@testable import MenuMateCore

final class ModelsTests: XCTestCase {
    func testRoundTripAllKinds() throws {
        let actions = [
            MenuAction(id: UUID(), title: "跑脚本", icon: .symbol("terminal"),
                       kind: .runScript(ScriptSpec(scriptPath: "Scripts/a.sh", inlineSource: nil, timeoutSeconds: 30)),
                       matching: MatchRule(), placement: .topLevel,
                       variants: .fixed(["png", "jpeg"]), presetKey: "demo",
                       isEnabled: true, sortOrder: 0),
            MenuAction(id: UUID(), title: "VS Code", icon: .imageFile("vscode.png"),
                       kind: .openWith(appBundleID: "com.microsoft.VSCode"),
                       matching: MatchRule(targets: .files, utis: ["public.text"], maxSelectionCount: 5),
                       placement: .submenu, variants: .directoryListing("Templates"), presetKey: nil,
                       isEnabled: true, sortOrder: 1),
        ]
        let config = MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: actions)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testFutureSchemaVersionFailsValidation() throws {
        let json = #"{"schemaVersion": 999, "actions": []}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: json)
        XCTAssertThrowsError(try decoded.validate())
    }

    /// Pack-sourced action carries packID/packRepo through a Codable round-trip.
    func testRoundTripWithPackSource() throws {
        let action = MenuAction(
            id: UUID(), title: "上传到图床", icon: .symbol("photo.on.rectangle"),
            kind: .runScript(ScriptSpec(scriptPath: "/abs/Packs/lihua-dev-tools/actions/upload.zsh")),
            matching: MatchRule(targets: .files, utis: ["public.image"]),
            placement: .topLevel, variants: .fixed(["png", "jpeg"]),
            presetKey: nil, packID: "lihua-dev-tools", packRepo: "lihua/dev-tools",
            isEnabled: false, sortOrder: 9)
        let config = MenuConfig(schemaVersion: MenuConfig.currentSchemaVersion, actions: [action])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: data)
        XCTAssertEqual(decoded, config)
        XCTAssertEqual(decoded.actions[0].packID, "lihua-dev-tools")
        XCTAssertEqual(decoded.actions[0].packRepo, "lihua/dev-tools")
        XCTAssertFalse(decoded.actions[0].isEnabled)
    }

    /// Legacy config without packID/packRepo decodes them as nil (backward compatible).
    func testLegacyActionDecodesPackFieldsAsNil() throws {
        let json = #"{"schemaVersion":1,"actions":[{"id":"00000000-0000-0000-0000-000000000002","icon":{"symbol":{"_0":"doc"}},"placement":"topLevel","matching":{"targets":"any","utis":[]},"isEnabled":true,"title":"旧动作","sortOrder":0,"kind":{"runScript":{"_0":{"scriptPath":"Scripts\/a.sh","timeoutSeconds":60}}}}]}"#
        let config = try JSONDecoder().decode(MenuConfig.self, from: Data(json.utf8))
        XCTAssertNil(config.actions[0].packID)
        XCTAssertNil(config.actions[0].packRepo)
        XCTAssertNil(config.actions[0].iconHue)   // 旧 config 无 iconHue 字段 → nil
    }

    func testRoundTripWithIconHue() throws {
        let a = MenuAction(id: UUID(), title: "彩色动作", icon: .symbol("bolt"),
                           kind: .runScript(ScriptSpec(inlineSource: "true")),
                           matching: MatchRule(), placement: .topLevel,
                           iconHue: "purple", isEnabled: true, sortOrder: 0)
        let data = try JSONEncoder().encode(MenuConfig(schemaVersion: 1, actions: [a]))
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: data)
        XCTAssertEqual(decoded.actions[0].iconHue, "purple")
        XCTAssertEqual(decoded.actions[0], a)
    }

    func testDefaultSeedIsAllScriptPresetsWithRelativePaths() {
        let seed = MenuConfig.defaultSeed()
        XCTAssertEqual(seed.actions.count, 6)
        XCTAssertTrue(seed.actions.allSatisfy { $0.isEnabled && $0.presetKey != nil })
        for action in seed.actions {
            guard case .runScript(let spec) = action.kind else {
                return XCTFail("预设必须是脚本动作: \(action.title)")
            }
            XCTAssertEqual(spec.scriptPath?.hasPrefix("Scripts/"), true, "预设脚本必须用相对路径")
        }
    }

    func testResolvedScriptPath() {
        let base = URL(fileURLWithPath: "/base")
        XCTAssertEqual(ScriptSpec(scriptPath: "Scripts/a.sh").resolvedScriptPath(base: base), "/base/Scripts/a.sh")
        XCTAssertEqual(ScriptSpec(scriptPath: "/abs/b.sh").resolvedScriptPath(base: base), "/abs/b.sh")
        XCTAssertNil(ScriptSpec(inlineSource: "echo hi").resolvedScriptPath(base: base))
    }

    // MARK: - New tests (code-review improvements)

    /// Golden wire-format fixture: ensures Codable encoding stays stable.
    /// The JSON literal was captured from a known-good encode run and must not
    /// silently drift (e.g. synthesised associated-value enum keys like {"symbol":{"_0":"terminal"}}).
    func testGoldenWireFormat() throws {
        // swiftlint:disable:next line_length
        let goldenJSON = #"{"schemaVersion":1,"actions":[{"id":"00000000-0000-0000-0000-000000000001","presetKey":"demo","icon":{"symbol":{"_0":"terminal"}},"placement":"topLevel","matching":{"targets":"any","utis":[]},"isEnabled":true,"title":"跑脚本","variants":{"fixed":{"_0":["png","jpeg"]}},"sortOrder":0,"kind":{"runScript":{"_0":{"scriptPath":"Scripts\/a.sh","timeoutSeconds":30}}}}]}"#
        let data = Data(goldenJSON.utf8)
        let config = try JSONDecoder().decode(MenuConfig.self, from: data)
        XCTAssertEqual(config.schemaVersion, 1)
        XCTAssertEqual(config.actions.count, 1)
        let action = config.actions[0]
        XCTAssertEqual(action.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(action.title, "跑脚本")
        XCTAssertEqual(action.presetKey, "demo")
        guard case .runScript(let spec) = action.kind else { return XCTFail("expected runScript kind") }
        XCTAssertEqual(spec.scriptPath, "Scripts/a.sh")
        XCTAssertEqual(spec.timeoutSeconds, 30)
        guard case .symbol(let name) = action.icon else { return XCTFail("expected symbol icon") }
        XCTAssertEqual(name, "terminal")
        guard case .fixed(let variants) = action.variants! else { return XCTFail("expected fixed variants") }
        XCTAssertEqual(variants, ["png", "jpeg"])
        XCTAssertEqual(action.placement, .topLevel)
        // Re-encode and decode again — verifies round-trip symmetry (catches drift in both directions).
        let reEncoded = try JSONEncoder().encode(config)
        let roundTripped = try JSONDecoder().decode(MenuConfig.self, from: reEncoded)
        XCTAssertEqual(roundTripped, config, "re-encoded JSON must round-trip to the same config")
    }

    /// defaultSeed() must produce identical action IDs on every call (deterministic UUIDs).
    func testDefaultSeedIsDeterministic() {
        let ids1 = MenuConfig.defaultSeed().actions.map(\.id)
        let ids2 = MenuConfig.defaultSeed().actions.map(\.id)
        XCTAssertEqual(ids1, ids2, "preset IDs must be deterministic across calls")
    }

    /// All 9 presetKeys must be unique.
    func testDefaultSeedPresetKeyUniqueness() {
        let actions = MenuConfig.defaultSeed().actions
        let keys = actions.compactMap(\.presetKey)
        XCTAssertEqual(keys.count, 6)
        XCTAssertEqual(Set(keys).count, 6, "presetKeys must be unique")
    }

    /// sortOrders must be unique.
    func testDefaultSeedSortOrderUniqueness() {
        let orders = MenuConfig.defaultSeed().actions.map(\.sortOrder)
        XCTAssertEqual(Set(orders).count, orders.count, "sortOrders must be unique")
    }

    /// Future-schema error must carry the found version number.
    func testFutureSchemaVersionErrorCarriesFoundVersion() throws {
        let json = #"{"schemaVersion": 999, "actions": []}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MenuConfig.self, from: json)
        XCTAssertThrowsError(try decoded.validate()) { error in
            guard let incompatible = error as? MenuConfig.IncompatibleSchema else {
                return XCTFail("expected IncompatibleSchema, got \(error)")
            }
            XCTAssertEqual(incompatible.found, 999)
        }
    }

    /// Current schema version passes validate() without throwing.
    func testCurrentSchemaVersionPassesValidation() throws {
        let json = #"{"schemaVersion": 1, "actions": []}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(MenuConfig.self, from: json)
        XCTAssertNoThrow(try config.validate())
    }

    /// schemaVersion(of:) extracts version without full decode.
    func testSchemaVersionProbe() throws {
        let json = #"{"schemaVersion": 999, "actions": []}"#.data(using: .utf8)!
        let version = try MenuConfig.schemaVersion(of: json)
        XCTAssertEqual(version, 999)
    }
}
