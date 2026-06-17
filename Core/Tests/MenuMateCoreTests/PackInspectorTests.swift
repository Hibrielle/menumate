import XCTest
@testable import MenuMateCore

final class PackInspectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, _ s: String) throws {
        try s.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testSurfacesUndeclaredScriptAndSkipsMetadataAndDeclared() throws {
        try write("manifest.json", "{}")
        try write("declared.sh", "echo hi")
        try write("helper.sh", "echo sneaky")   // undeclared sibling sourced via pack_root
        try write("README.md", "# docs")
        try write("LICENSE", "MIT")
        let extras = PackInspector.undeclaredFiles(inDirectory: dir, declared: ["declared.sh"])
        XCTAssertEqual(extras.map(\.relativePath), ["helper.sh"],
                       "only the undeclared code file should surface; manifest/declared/README/LICENSE are skipped")
    }

    func testSurfacesHiddenScript() throws {
        try write("manifest.json", "{}")
        try write(".evil.sh", "rm -rf ~")   // hidden script must NOT be skipped
        let extras = PackInspector.undeclaredFiles(inDirectory: dir, declared: [])
        XCTAssertEqual(extras.map(\.relativePath), [".evil.sh"])
    }

    func testFlagsExecutableAndBinary() throws {
        try write("run.sh", "echo x")
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: dir.appendingPathComponent("run.sh").path)
        try Data([0x7f, 0x45, 0x4c, 0x46, 0x00, 0x01]).write(to: dir.appendingPathComponent("tool"))
        let extras = PackInspector.undeclaredFiles(inDirectory: dir, declared: [])
        let byPath = Dictionary(uniqueKeysWithValues: extras.map { ($0.relativePath, $0) })
        XCTAssertEqual(byPath["run.sh"]?.isExecutable, true)
        XCTAssertEqual(byPath["tool"]?.isBinary, true, "NUL byte → binary")
    }

    func testResolvesInsideRejectsSymlinkEscape() throws {
        try write("ok.sh", "echo ok")
        XCTAssertTrue(PackInspector.resolvesInside(directory: dir, relativePath: "ok.sh"))
        // a "safe-looking" relative path that is actually a symlink out of the pack
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("escape.sh"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertFalse(PackInspector.resolvesInside(directory: dir, relativePath: "escape.sh"))
        XCTAssertFalse(PackInspector.resolvesInside(directory: dir, relativePath: "../outside.sh"))
    }

    func testUndeclaredFilesFlagsSymlink() throws {
        try write("manifest.json", "{}")
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link.sh"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let extras = PackInspector.undeclaredFiles(inDirectory: dir, declared: [])
        XCTAssertEqual(extras.first { $0.relativePath == "link.sh" }?.isSymlink, true)
    }
}
