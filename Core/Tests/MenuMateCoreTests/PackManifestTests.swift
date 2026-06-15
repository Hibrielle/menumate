import XCTest
@testable import MenuMateCore

final class PackManifestTests: XCTestCase {

    // A fully-specified, valid manifest containing one directoryListing variant
    // action and one fixed variant action. Used as the round-trip fixture.
    private let fullJSON = #"""
    {
      "schemaVersion": 1,
      "name": "dev-tools",
      "author": "lihua",
      "description": "一组开发常用动作",
      "icon": "wrench.and.screwdriver",
      "actions": [
        {
          "id": "upload-imagebed",
          "title": "上传到图床",
          "icon": "photo.on.rectangle",
          "script": "actions/upload-to-imagebed.zsh",
          "targets": "files",
          "utis": ["public.image"],
          "placement": "topLevel",
          "variants": { "fixed": ["png", "jpeg"] },
          "timeoutSeconds": 120
        },
        {
          "id": "new-from-template",
          "title": "从模板新建",
          "icon": "doc.badge.plus",
          "script": "actions/new-from-template.zsh",
          "targets": "container",
          "placement": "submenu",
          "variants": { "directoryListing": "templates" }
        }
      ]
    }
    """#

    func testParseValidManifestWithBothVariantKinds() throws {
        let manifest = try PackManifest.decode(Data(fullJSON.utf8))
        try manifest.validate()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.name, "dev-tools")
        XCTAssertEqual(manifest.author, "lihua")
        XCTAssertEqual(manifest.description, "一组开发常用动作")
        XCTAssertEqual(manifest.icon, "wrench.and.screwdriver")
        XCTAssertEqual(manifest.actions.count, 2)

        let a0 = manifest.actions[0]
        XCTAssertEqual(a0.id, "upload-imagebed")
        XCTAssertEqual(a0.title, "上传到图床")
        XCTAssertEqual(a0.icon, "photo.on.rectangle")
        XCTAssertEqual(a0.script, "actions/upload-to-imagebed.zsh")
        XCTAssertEqual(a0.targets, .files)
        XCTAssertEqual(a0.utis, ["public.image"])
        XCTAssertEqual(a0.placement, .topLevel)
        XCTAssertEqual(a0.timeoutSeconds, 120)
        guard case .fixed(let list) = a0.variants else { return XCTFail("expected fixed variants") }
        XCTAssertEqual(list, ["png", "jpeg"])

        let a1 = manifest.actions[1]
        XCTAssertEqual(a1.id, "new-from-template")
        XCTAssertEqual(a1.targets, .container)
        XCTAssertEqual(a1.placement, .submenu)
        guard case .directoryListing(let dir) = a1.variants else {
            return XCTFail("expected directoryListing variants")
        }
        XCTAssertEqual(dir, "templates")
    }

    func testRoundTrip() throws {
        let manifest = try PackManifest.decode(Data(fullJSON.utf8))
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try PackManifest.decode(encoded)
        XCTAssertEqual(decoded, manifest)
    }

    func testDefaultsAreFilledIn() throws {
        // Minimal action: no icon, no author/description, no utis, no timeout, no placement, no variants.
        let json = #"""
        {
          "schemaVersion": 1,
          "name": "minimal",
          "actions": [
            { "id": "a", "title": "动作", "script": "actions/a.zsh", "targets": "any" }
          ]
        }
        """#
        let manifest = try PackManifest.decode(Data(json.utf8))
        try manifest.validate()

        XCTAssertNil(manifest.author)
        XCTAssertNil(manifest.description)
        XCTAssertEqual(manifest.icon, "shippingbox", "pack icon defaults to shippingbox")

        let a = manifest.actions[0]
        XCTAssertEqual(a.icon, "bolt", "action icon defaults to bolt")
        XCTAssertEqual(a.utis, [], "nil utis decode to empty array")
        XCTAssertEqual(a.timeoutSeconds, 60, "nil timeout defaults to 60")
        XCTAssertEqual(a.placement, .topLevel, "missing placement defaults to topLevel")
        XCTAssertNil(a.variants)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "name": "x",
          "futureTopLevelKey": { "anything": true },
          "actions": [
            { "id": "a", "title": "动作", "script": "actions/a.zsh", "targets": "any",
              "futureActionKey": 42 }
          ]
        }
        """#
        let manifest = try PackManifest.decode(Data(json.utf8))
        try manifest.validate()
        XCTAssertEqual(manifest.name, "x")
        XCTAssertEqual(manifest.actions.count, 1)
    }

    func testFutureSchemaVersionFailsValidation() throws {
        let json = #"{"schemaVersion": 999, "name": "x", "actions": [{"id":"a","title":"t","script":"actions/a.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate()) { error in
            guard case PackManifest.ValidationError.incompatibleSchema(let found) = error else {
                return XCTFail("expected incompatibleSchema, got \(error)")
            }
            XCTAssertEqual(found, 999)
        }
    }

    func testEmptyNameFailsValidation() throws {
        let json = #"{"schemaVersion": 1, "name": "  ", "actions": [{"id":"a","title":"t","script":"actions/a.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testEmptyActionsFailsValidation() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": []}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testActionWithEmptyIDFailsValidation() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"","title":"t","script":"actions/a.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testActionWithEmptyTitleFailsValidation() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"  ","script":"actions/a.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testDuplicateActionIDsFailValidation() throws {
        let json = #"""
        {"schemaVersion": 1, "name": "x", "actions": [
          {"id":"dup","title":"a","script":"actions/a.zsh","targets":"any"},
          {"id":"dup","title":"b","script":"actions/b.zsh","targets":"any"}
        ]}
        """#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    // MARK: - Script path safety (path traversal / absolute paths rejected)

    func testScriptPathWithParentTraversalIsRejected() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"t","script":"../../etc/passwd","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testScriptPathWithEmbeddedParentSegmentIsRejected() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"t","script":"actions/../../x.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testAbsoluteScriptPathIsRejected() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"t","script":"/etc/passwd","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testEmptyScriptPathIsRejected() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"t","script":"","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertThrowsError(try manifest.validate())
    }

    func testWellFormedRelativeScriptPathIsAccepted() throws {
        let json = #"{"schemaVersion": 1, "name": "x", "actions": [{"id":"a","title":"t","script":"actions/sub/a.zsh","targets":"any"}]}"#
        let manifest = try PackManifest.decode(Data(json.utf8))
        XCTAssertNoThrow(try manifest.validate())
    }
}
