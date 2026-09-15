import XCTest
@testable import MenuMateCore

final class PackDirectoryDiffTests: XCTestCase {
    private var root: URL!
    private var old: URL { root.appendingPathComponent("old") }
    private var new: URL { root.appendingPathComponent("new") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for dir in [old, new] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func put(_ path: String, _ text: String, in dir: URL) throws {
        let file = dir.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
    func testReviewsDependenciesHiddenFilesAndManifestEvenWhenEntrypointsDoNotChange() throws {
        for dir in [old, new] {
            try put("ui/index.html", "<script src='options.js'></script>", in: dir)
            try put("a.zsh", "print ok", in: dir)
        }
        for path in ["ui/options.js", "ui/style.css", ".hidden.js", "README.md", "manifest.json"] {
            try put(path, "v1", in: old); try put(path, "v2", in: new)
        }
        try put("removed.js", "old", in: old)
        try put("added.js", "new", in: new)
        try put(".git/config", "local only", in: old)
        let diffs = try PackDirectoryDiff.compare(old: old, new: new)
        XCTAssertEqual(Set(diffs.filter { !$0.isUnchanged }.map(\.path)),
                       ["ui/options.js", "ui/style.css", ".hidden.js", "README.md", "manifest.json", "removed.js", "added.js"])
        XCTAssertTrue(try XCTUnwrap(diffs.first { $0.path == "removed.js" }).isRemoved)
        XCTAssertTrue(try XCTUnwrap(diffs.first { $0.path == "added.js" }).isAdded)
        XCTAssertTrue(try XCTUnwrap(diffs.first { $0.path == "ui/index.html" }).isUnchanged)
        XCTAssertFalse(diffs.contains { $0.path.hasPrefix(".git") })
    }
    func testBinaryLargeFilePermissionsAndSymlinkChangesAreVisible() throws {
        for (dir, byte) in [(old, UInt8(1)), (new, UInt8(2))] {
            try Data([0, byte]).write(to: dir.appendingPathComponent("asset.bin"))
            var large = Data(repeating: 65, count: 300_000); large.append(byte)
            try large.write(to: dir.appendingPathComponent("large.txt"))
            try put("script.zsh", "print ok", in: dir)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: old.appendingPathComponent("script.zsh").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: new.appendingPathComponent("script.zsh").path)
        // Nonexistent/outside targets must be shown without dereferencing them.
        try FileManager.default.createSymbolicLink(atPath: old.appendingPathComponent("link").path, withDestinationPath: "/not-a-real-target-one")
        try FileManager.default.createSymbolicLink(atPath: new.appendingPathComponent("link").path, withDestinationPath: "/not-a-real-target-two")
        let diffs = try PackDirectoryDiff.compare(old: old, new: new)
        XCTAssertEqual(diffs.filter(\.isModified).count, 4)
        let binary = try XCTUnwrap(diffs.first { $0.path == "asset.bin" })
        XCTAssertTrue(binary.newText!.contains("SHA-256"))
        XCTAssertNotEqual(binary.oldText, binary.newText)
        XCTAssertLessThan(diffs.first { $0.path == "large.txt" }!.newText!.count, 200)
        XCTAssertTrue(diffs.first { $0.path == "link" }!.newText!.contains("not-a-real-target-two"))
    }
    func testMissingTreeAbortsReview() {
        XCTAssertThrowsError(try PackDirectoryDiff.compare(old: old, new: root.appendingPathComponent("missing")))
    }
    func testSymlinkedRootDoesNotFollowDirectoryEntriesOutsidePack() throws {
        let alias = root.appendingPathComponent("alias")
        let outside = root.appendingPathComponent("outside")
        try put("private.txt", "Do not read through link", in: outside)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: old)
        for dir in [old, new] {
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("external"), withDestinationURL: outside)
        }
        let diffs = try PackDirectoryDiff.compare(old: alias, new: new)
        XCTAssertEqual(diffs.map(\.path), ["external"])
        XCTAssertTrue(diffs[0].isUnchanged)
        XCTAssertFalse(diffs[0].oldText!.contains("Do not read"))
    }

}
