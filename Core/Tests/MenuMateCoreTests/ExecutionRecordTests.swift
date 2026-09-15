import XCTest
@testable import MenuMateCore

final class ExecutionRecordTests: XCTestCase {
    private func record(_ title: String = "Convert", result: ShellResult = ShellResult(exitCode: 0, stdout: "Created output.png\nDetails", stderr: "", timedOut: false)) -> ExecutionRecord {
        ExecutionRecord(title: title, paths: ["/tmp/图片 sample.jpeg"], variant: "png", result: result, duration: 0.25)
    }
    func testLegacyRecordsDecodeWithoutNewMetadata() throws {
        let data = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","date":0,"title":"Old action","success":true,"detail":"Old output"}]"#.utf8)
        let old = try JSONDecoder().decode([ExecutionRecord].self, from: data)[0]
        XCTAssertEqual(old.detail, "Old output")
        XCTAssertNil(old.duration); XCTAssertNil(old.paths); XCTAssertNil(old.exitCode)
        XCTAssertTrue(old.matches(query: "old output"))
    }
    func testStoresBothStreamsAndTimeoutIsNotSuccess() throws {
        let result = ShellResult(exitCode: 0, stdout: "partial output", stderr: "process timed out", timedOut: true)
        let item = record(result: result)
        XCTAssertFalse(item.success)
        XCTAssertEqual(item.stdout, "partial output")
        XCTAssertEqual(item.stderr, "process timed out")
        XCTAssertEqual(item.duration, 0.25)
        XCTAssertTrue(ExecutionResultFilter.failed.matches(item))
        XCTAssertFalse(ExecutionResultFilter.succeeded.matches(item))
        XCTAssertEqual(try JSONDecoder().decode(ExecutionRecord.self, from: JSONEncoder().encode(item)), item)
    }
    func testSearchMatchesFileNamesOutputAndOptions() {
        let item = record()
        for query in ["convert", "图片 sample", "output.png", "png", "  "] {
            XCTAssertTrue(item.matches(query: query), query)
        }
        XCTAssertFalse(item.matches(query: "missing"))
        XCTAssertTrue(ExecutionResultFilter.succeeded.matches(item))
    }
    func testBoundsHistoryOutputAndInputPaths() {
        let item = ExecutionRecord(title: "Long", paths: (0..<100).map { "/tmp/\($0)" }, variant: nil,
            result: ShellResult(exitCode: 1, stdout: String(repeating: "a", count: 20_000), stderr: String(repeating: "b", count: 18_000), timedOut: false), duration: 2)
        XCTAssertEqual(item.stdout?.count, 16_000)
        XCTAssertEqual(item.stderr?.count, 16_000)
        XCTAssertEqual(item.paths?.count, 20)
        XCTAssertEqual(item.selectionCount, 100)
        XCTAssertEqual(item.outputTruncated, true)
    }
    func testStoreRetainsNewestFiftyAndCorruptionIsNotSilentlyCleared() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExecutionLogStore(directory: root)
        XCTAssertTrue(try store.load().isEmpty)
        try store.save((0..<60).map { record("Record \($0)") })
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 50)
        XCTAssertEqual(loaded.first?.title, "Record 0")
        let invalid = Data("invalid log".utf8)
        try invalid.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), invalid)
        try store.save([])
        XCTAssertTrue(try store.load().isEmpty)
    }
    func testWriteFailureIsReported() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExecutionLogStore(directory: root)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        let marker = store.fileURL.appendingPathComponent("keep")
        try Data("keep".utf8).write(to: marker)
        XCTAssertThrowsError(try store.save([record()]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }
}
