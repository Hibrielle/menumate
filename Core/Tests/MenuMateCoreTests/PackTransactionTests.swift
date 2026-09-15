import XCTest
@testable import MenuMateCore

final class PackTransactionTests: XCTestCase {
    private enum Injected: Error { case failure }
    private func fixture() throws -> (URL, URL, MenuConfig, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let old = root.appendingPathComponent("Packs/test")
        let replacement = root.appendingPathComponent("replacement")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try Data("old script".utf8).write(to: old.appendingPathComponent("script"))
        try Data("new script".utf8).write(to: replacement.appendingPathComponent("script"))
        let config = MenuConfig(schemaVersion: 1, actions: [])
        try ConfigStore(directory: root).save(config)
        try Data("old registry".utf8).write(to: root.appendingPathComponent("Packs/installed.json"))
        return (root, replacement, config, try Data(contentsOf: root.appendingPathComponent("config.json")))
    }
    func testEveryPrecommitFailureRestoresExactFiles() throws {
        for point in [PackTransaction.Step.prepared, .oldPackMoved, .newPackMoved, .installedWritten, .configWritten] {
            let (root, replacement, config, bytes) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let tx = PackTransaction(directory: root) { if $0 == point { throw Injected.failure } }
            XCTAssertThrowsError(try tx.apply(key: "test", replacement: replacement, config: config,
                                              installed: Data("new registry".utf8), expectedConfig: config, expectedInstalled: Data("old registry".utf8)))
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("config.json")), bytes)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/test/script")), "old script")
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/installed.json")), "old registry")
            XCTAssertFalse(tx.needsRecovery)
            XCTAssertTrue(FileManager.default.fileExists(atPath: replacement.path)) // retry uses reviewed source
        }
    }
    func testRollbackFailureRetainsJournalAndBlocksConfigWrites() throws {
        let (root, replacement, config, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tx = PackTransaction(directory: root) {
            if $0 == .configWritten || $0 == .rollbackPackRestored { throw Injected.failure }
        }
        XCTAssertThrowsError(try tx.apply(key: "test", replacement: replacement, config: config,
                                          installed: Data("new registry".utf8), expectedConfig: config, expectedInstalled: Data("old registry".utf8)))
        XCTAssertTrue(tx.needsRecovery)
        XCTAssertThrowsError(try ConfigStore(directory: root).save(config))
        XCTAssertTrue(try PackTransaction(directory: root).recover())
        XCTAssertFalse(try PackTransaction(directory: root).recover())
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/test/script")), "old script")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/installed.json")), "old registry")
    }
    func testStaleConfigurationIsRejectedBeforeChangingFiles() throws {
        let (root, replacement, config, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var changed = config
        changed.actions = MenuConfig.defaultSeed().actions
        try ConfigStore(directory: root).save(changed)
        XCTAssertThrowsError(try PackTransaction(directory: root).apply(key: "test", replacement: replacement,
                              config: config, installed: Data(), expectedConfig: config, expectedInstalled: Data("old registry".utf8)))
        XCTAssertEqual(try ConfigStore(directory: root).load(), changed)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/test/script")), "old script")
    }
    func testRegistryConflictAndStagingFailureLeaveInstallationUntouched() throws {
        let (root, replacement, config, bytes) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tx = PackTransaction(directory: root)
        XCTAssertThrowsError(try tx.apply(key: "test", replacement: replacement, config: config,
            installed: Data(), expectedConfig: config, expectedInstalled: Data("stale registry".utf8)))
        XCTAssertFalse(tx.needsRecovery)
        XCTAssertThrowsError(try tx.apply(key: "test", replacement: root.appendingPathComponent("missing"), config: config,
            installed: Data(), expectedConfig: config, expectedInstalled: Data("old registry".utf8)))
        XCTAssertFalse(tx.needsRecovery)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("config.json")), bytes)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Packs/test/script"), encoding: .utf8), "old script")
    }

    func testConfigCompareAndSwapRejectsConcurrentChanges() throws {
        let (root, _, config, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(directory: root)
        var external = config
        external.actions = MenuConfig.defaultSeed().actions
        try store.save(external)
        XCTAssertThrowsError(try store.save(config, expected: config))
        XCTAssertEqual(try store.load(fresh: true), external)
    }

    func testInvalidJournalAndKeysArePreservedOrRejected() throws {
        let (root, replacement, config, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tx = PackTransaction(directory: root)
        for key in ["../escape", "installed.json", ".", ""] {
            XCTAssertThrowsError(try tx.apply(key: key, replacement: replacement, config: config,
                                              installed: Data(), expectedConfig: config, expectedInstalled: Data("old registry".utf8)))
        }
        let dir = root.appendingPathComponent(".pack-transaction")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try tx.recover())
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("journal.json")), "broken")
    }
}
