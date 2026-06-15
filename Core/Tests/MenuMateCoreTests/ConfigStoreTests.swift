import XCTest
@testable import MenuMateCore

final class ConfigStoreTests: XCTestCase {
    private func freshDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = ConfigStore(directory: freshDir())
        let config = MenuConfig(schemaVersion: 1, actions: [])
        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testLoadMissingFileReturnsDefaultSeed() throws {
        let config = try ConfigStore(directory: freshDir()).load()
        XCTAssertEqual(config, MenuConfig.defaultSeed())
    }

    func testCacheInvalidatesWhenFileChanges() throws {
        let dir = freshDir()
        let store = ConfigStore(directory: dir)
        try store.save(MenuConfig(schemaVersion: 1, actions: []))
        _ = try store.load()
        var newer = MenuConfig.defaultSeed()
        newer.actions[0].title = "改过了"
        // 用第二个 store 实例写入，模拟主 App 写、扩展读
        usleep(10_000)
        try ConfigStore(directory: dir).save(newer)
        XCTAssertEqual(try store.load().actions.first?.title, "改过了")
    }

    func testCorruptJSONThrows() throws {
        let dir = freshDir()
        let store = ConfigStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    func testFutureVersionFileThrowsIncompatibleSchemaBeforeFullDecode() throws {
        let dir = freshDir()
        let store = ConfigStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // actions 故意是 v1 解不开的形状——两阶段探测应在完整 decode 前就抛 IncompatibleSchema
        let future = #"{"schemaVersion": 2, "actions": [{"unknownShape": true}]}"#
        try Data(future.utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual((error as? MenuConfig.IncompatibleSchema)?.found, 2)
        }
    }
}
