import XCTest
@testable import MenuMateCore

final class IPCTests: XCTestCase {
    func testRoundTrip() throws {
        let request = ActionRequest(actionID: UUID(), variant: "png", paths: ["/tmp/a", "/tmp/b c"])
        let decoded = try ActionRequest.decode(try request.encodedString())
        XCTAssertEqual(decoded, request)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ActionRequest.decode("not-json")) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testEmptyPathsDecodes() throws {
        // 空 paths 在本层是合法载荷——拒绝与否是主 App 监听端校验的职责
        let request = ActionRequest(actionID: UUID(), paths: [])
        XCTAssertEqual(try ActionRequest.decode(try request.encodedString()).paths, [])
    }

    func testNotificationNamesAreStable() {
        XCTAssertEqual(IPC.actionNotification, "com.menumate.action")
        XCTAssertEqual(IPC.heartbeatNotification, "com.menumate.heartbeat")
        XCTAssertEqual(IPC.snapshotNotification, "com.menumate.snapshot")
        XCTAssertEqual(IPC.snapshotRequestNotification, "com.menumate.snapshot-request")
    }

    func testMaxPathsConstant() {
        // 扩展画菜单与主 App 派发闸门共用此常量，必须一致
        XCTAssertEqual(IPC.maxPaths, 1000)
    }

    func testExtensionSnapshotRoundTrip() throws {
        // 含一个 directoryListing 动作（new-file）与其预解析列举
        let config = MenuConfig.defaultSeed()
        let newFileID = try XCTUnwrap(config.actions.first { $0.presetKey == "new-file" }).id
        let snapshot = ExtensionSnapshot(config: config,
                                         variantListings: [newFileID: ["文本.txt", "Markdown.md"]])
        let decoded = try ExtensionSnapshot.decode(try snapshot.encodedString())
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.config.actions.count, 6)
        XCTAssertEqual(decoded.variantListings[newFileID], ["文本.txt", "Markdown.md"])
    }

    func testExtensionSnapshotGarbageThrows() {
        XCTAssertThrowsError(try ExtensionSnapshot.decode("not-json"))
    }

    func testEndToEndSnapshotThroughChunkingToMenu() throws {
        // 完整复刻扩展路径:App 编码 → 分块 → 每块封装 → 扩展逐条解码 → 重组 → 解码快照 → 画菜单。
        let config = MenuConfig.defaultSeed()
        let newFile = try XCTUnwrap(config.actions.first { $0.presetKey == "new-file" })
        let snapshot = ExtensionSnapshot(
            config: config,
            variantListings: [newFile.id: ["A.txt", "B.md"]],
            iconImages: [try XCTUnwrap(config.actions.first).id.uuidString: "iVBORw0KGgo="])

        // App 端:编码 + 分块(小 limit 强制多块)+ 每块封装为线缆字符串。
        let payload = try snapshot.encodedString()
        let wire = try ChunkedTransport.split(payload, limit: 64).map { try $0.encodedString() }
        XCTAssertGreaterThan(wire.count, 1, "payload should span multiple chunks at this limit")

        // 扩展端:逐条解码 + 重组 + 解码快照。
        let reassembler = ChunkReassembler()
        var assembled: String?
        for s in wire {
            if let done = reassembler.receive(try ChunkedTransport.Chunk.decode(s)) { assembled = done }
        }
        let decoded = try ExtensionSnapshot.decode(try XCTUnwrap(assembled))
        XCTAssertEqual(decoded, snapshot)

        // 扩展端:用收到的快照真正画一遍菜单(空白处 → 新建文件子菜单按注入列举展开)。
        let specs = MenuBuilder.build(MenuBuildInput(
            config: decoded.config, context: .container(FileManager.default.temporaryDirectory),
            heartbeatFresh: true, variantListings: decoded.variantListings))
        XCTAssertEqual(specs.first { $0.title == newFile.title }?.children.map(\.title), ["A.txt", "B.md"])
    }

    func testExtensionSnapshotIconImagesRoundTrip() throws {
        // 带自定义图片图标字节的快照编解码一致
        let config = MenuConfig.defaultSeed()
        let actionID = try XCTUnwrap(config.actions.first).id
        let snapshot = ExtensionSnapshot(
            config: config,
            variantListings: [:],
            iconImages: [actionID.uuidString: "iVBORw0KGgo=", "other": "AAAA"])
        let decoded = try ExtensionSnapshot.decode(try snapshot.encodedString())
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.iconImages[actionID.uuidString], "iVBORw0KGgo=")
        XCTAssertEqual(decoded.iconImages["other"], "AAAA")
    }

    func testExtensionSnapshotDefaultIconImagesEmpty() {
        // 未提供 iconImages 时默认为空字典
        let snapshot = ExtensionSnapshot(config: .defaultSeed(), variantListings: [:])
        XCTAssertTrue(snapshot.iconImages.isEmpty)
    }

    func testExtensionSnapshotLegacyJSONDecodesEmptyIconImages() throws {
        // 旧 JSON（无 iconImages 字段）向后兼容：解码为空字典。
        // 注意 variantListings 为 [UUID:[String]]，JSONEncoder 将非字符串键字典编为数组，
        // 故旧格式 variantListings 为 []。
        let legacy = """
        {"config":{"schemaVersion":1,"actions":[]},"variantListings":[]}
        """
        let decoded = try ExtensionSnapshot.decode(legacy)
        XCTAssertTrue(decoded.iconImages.isEmpty)
        XCTAssertEqual(decoded.config.actions.count, 0)
    }
}
