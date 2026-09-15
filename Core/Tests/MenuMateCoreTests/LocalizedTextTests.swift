import XCTest
@testable import MenuMateCore

final class LocalizedTextTests: XCTestCase {
    func testExactRegionalAndFallbackNames() {
        let translations = ["en": "English", "en-GB": "British", "zh-Hans": "简体", "zh-Hant": "繁體"]
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "en_GB"), "British")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "en-US"), "English")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "zh-Hans-CN"), "简体")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "zh-CN"), "简体")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "zh-HK"), "繁體")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: ["zh-Hans": "简体"], language: "zh-TW"), "Default")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: ["en": "  "], language: "en"), "Default")
        XCTAssertEqual(LocalizedText.resolve("Default", translations: translations, language: "fr"), "Default")
    }
    func testManifestTranslationsRoundTripAndLegacyStillDecodes() throws {
        let manifest = try PackManifest.decode(Data(#"{"schemaVersion":1,"name":"Default pack","localizedNames":{"en":"Tools","zh-Hans":"工具"},"localizedDescriptions":{"zh-Hans":"说明"},"actions":[{"id":"a","title":"Default action","script":"a.zsh","localizedTitles":{"en":"Copy","zh-Hans":"复制"}}]}"#.utf8))
        try manifest.validate()
        XCTAssertEqual(try PackManifest.decode(JSONEncoder().encode(manifest)), manifest)
        XCTAssertEqual(LocalizedText.resolve(manifest.name, translations: manifest.localizedNames, language: "zh-Hans"), "工具")
        let legacy = try PackManifest.decode(Data(#"{"name":"Old","actions":[{"id":"a","title":"Old action","script":"a.zsh"}]}"#.utf8))
        XCTAssertNil(legacy.localizedNames); XCTAssertNil(legacy.actions[0].localizedTitles)
    }
    func testFinderUsesSnapshotLanguageAndKeepsVariantValuesStable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var action = MenuAction(id: UUID(), title: "Default", icon: .symbol("bolt"),
            kind: .runScript(ScriptSpec(inlineSource: "true")), matching: MatchRule(targets: .container),
            placement: .topLevel, variants: .fixed(["keep-extension", "without-extension"]),
            isEnabled: true, sortOrder: 0, localizedTitles: ["en": "Copy name", "zh-Hans": "复制名称"])
        let config = MenuConfig(schemaVersion: 1, actions: [action])
        let snapshot = ExtensionSnapshot(config: config, variantListings: [:], language: "en")
        let decoded = try ExtensionSnapshot.decode(snapshot.encodedString())
        XCTAssertEqual(decoded.language, "en")
        let menu = MenuBuilder.build(MenuBuildInput(config: decoded.config, context: .container(root), heartbeatFresh: true, variantListings: [:], language: decoded.language!))
        XCTAssertEqual(menu[0].title, "Copy name")
        XCTAssertEqual(menu[0].children[1].request?.variant, "without-extension")
        XCTAssertEqual(menu[0].children[0].request?.actionID, action.id)
        action.variants = nil; action.interface = ActionInterface(entry: "index.html")
        let interactive = MenuBuilder.build(MenuBuildInput(config: MenuConfig(schemaVersion: 1, actions: [action]), context: .container(root), heartbeatFresh: true, variantListings: [:], language: "zh-Hans"))
        XCTAssertEqual(interactive[0].title, "复制名称…")
        action.localizedTitles = nil
        let old = try JSONDecoder().decode(MenuAction.self, from: JSONEncoder().encode(action))
        XCTAssertNil(old.localizedTitles)
        XCTAssertEqual(old.title(in: "en"), "Default")
    }
    func testUpdatePreservesOverridesAndExplicitlyRemovedTranslations() {
        let result = LocalizedText.merging(upstream: ["en": "New", "zh-Hans": "新", "ja": "追加"],
            previous: ["en": "Old", "zh-Hans": "旧"], local: ["en": "Mine"])
        XCTAssertEqual(result, ["en": "Mine", "ja": "追加"])
        XCTAssertEqual(LocalizedText.merging(upstream: ["en": "New"], previous: ["en": "Old"], local: ["en": "Old"]), ["en": "New"])
    }
}
