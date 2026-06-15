import XCTest
@testable import MenuMateCore

final class ChunkedTransportTests: XCTestCase {

    // MARK: - split + Chunk 编解码

    func testSingleChunkRoundTrip() throws {
        let payload = #"{"hello":"world"}"#
        let chunks = ChunkedTransport.split(payload)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[0].total, 1)
        XCTAssertEqual(chunks[0].data, payload)
        let decoded = try ChunkedTransport.Chunk.decode(try chunks[0].encodedString())
        XCTAssertEqual(decoded, chunks[0])
        let reassembler = ChunkReassembler()
        XCTAssertEqual(reassembler.receive(decoded), payload)
    }

    func testMultiChunkSplitAndOutOfOrderReassembly() {
        let payload = String(repeating: "abcdefg-", count: 20)   // 160 字节，limit 10 → 16 块
        let chunks = ChunkedTransport.split(payload, limit: 10)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(Set(chunks.map(\.id)).count, 1, "同一载荷的所有块共享 id")
        XCTAssertEqual(chunks.map(\.index), Array(0..<chunks.count), "index 必须 0-based 连续")
        XCTAssertTrue(chunks.allSatisfy { $0.total == chunks.count })
        XCTAssertEqual(chunks.map(\.data).joined(), payload)
        let reassembler = ChunkReassembler()
        var result: String?
        for chunk in chunks.shuffled() {
            if let assembled = reassembler.receive(chunk) {
                XCTAssertNil(result, "凑齐只应发生一次")
                result = assembled
            }
        }
        XCTAssertEqual(result, payload)
    }

    func testSplitRespectsCharacterBoundaries() {
        // 中文 3 字节、emoji 4 字节、国旗 8 字节——任何一块都不得切坏字符
        let payload = "中文🙂🇨🇳字符emoji混合📦test中文末尾🙂"
        let chunks = ChunkedTransport.split(payload, limit: 10)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.data.utf8.count, 10)
        }
        XCTAssertEqual(chunks.map(\.data).joined(), payload)
    }

    func testEmptyPayloadYieldsSingleEmptyChunk() {
        let chunks = ChunkedTransport.split("")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].index, 0)
        XCTAssertEqual(chunks[0].total, 1)
        XCTAssertEqual(chunks[0].data, "")
        let reassembler = ChunkReassembler()
        XCTAssertEqual(reassembler.receive(chunks[0]), "")
    }

    func testEnvelopeOverheadStaysUnderReceiverCap() throws {
        // 接收端闸门是 64KB/条：路径密集型载荷（含大量 / 与 "）经 JSON 信封编码后的
        // 膨胀必须仍在闸门以内，否则块会被静默丢弃。
        var payload = "["
        while payload.utf8.count < 200 * 1024 {
            payload += #""\/Users\/某用户\/项目 目录\/file \"name\".txt","#
        }
        payload += "]"
        for chunk in ChunkedTransport.split(payload) {
            XCTAssertLessThanOrEqual(chunk.data.utf8.count, ChunkedTransport.chunkLimit)
            XCTAssertLessThanOrEqual(try chunk.encodedString().utf8.count, 64 * 1024)
        }
    }

    func testWorstCaseEscapeDensityStaysUnderReceiverCap() throws {
        // 全部由需二次转义的字符组成(最坏 2× 膨胀)
        let payload = String(repeating: "\"\\", count: 60_000)   // 120KB 的引号反斜杠
        for chunk in ChunkedTransport.split(payload) {
            XCTAssertLessThanOrEqual(chunk.data.utf8.count, ChunkedTransport.chunkLimit)
            XCTAssertLessThanOrEqual(try chunk.encodedString().utf8.count, 64 * 1024, "信封含最坏转义后必须低于接收端 64KB 闸门")
        }
        // 重组完整性
        let r = ChunkReassembler()
        var out: String?
        for c in ChunkedTransport.split(payload) { out = r.receive(c) ?? out }
        XCTAssertEqual(out, payload)
    }

    // MARK: - ChunkReassembler 防御

    func testReassemblerRejectsTooManyChunks() {
        let reassembler = ChunkReassembler(maxChunks: 4)
        XCTAssertNil(reassembler.receive(.init(id: UUID(), index: 0, total: 5, data: "x")))
        // total 在上限内则正常工作
        let id = UUID()
        XCTAssertNil(reassembler.receive(.init(id: id, index: 0, total: 2, data: "a")))
        XCTAssertEqual(reassembler.receive(.init(id: id, index: 1, total: 2, data: "b")), "ab")
    }

    func testReassemblerRejectsIndexOutOfBounds() {
        let reassembler = ChunkReassembler()
        XCTAssertNil(reassembler.receive(.init(id: UUID(), index: 2, total: 2, data: "x")))
        XCTAssertNil(reassembler.receive(.init(id: UUID(), index: -1, total: 2, data: "x")))
        XCTAssertNil(reassembler.receive(.init(id: UUID(), index: 0, total: 0, data: "x")))
    }

    func testReassemblerRejectsTotalMismatch() {
        let reassembler = ChunkReassembler()
        let id = UUID()
        XCTAssertNil(reassembler.receive(.init(id: id, index: 0, total: 3, data: "a")))
        // total 与已记录不符 → 拒绝该块，且不得让攻击方借此挤掉合法半成品
        XCTAssertNil(reassembler.receive(.init(id: id, index: 1, total: 2, data: "x")))
        XCTAssertNil(reassembler.receive(.init(id: id, index: 1, total: 3, data: "b")))
        XCTAssertEqual(reassembler.receive(.init(id: id, index: 2, total: 3, data: "c")), "abc")
    }

    func testReassemblerDropsWholeEntryWhenBytesExceedBudget() {
        let reassembler = ChunkReassembler(maxTotalBytes: 10)
        let id = UUID()
        XCTAssertNil(reassembler.receive(.init(id: id, index: 0, total: 3, data: "12345678")))
        // 累计 13 字节 > 10 → 整条丢弃
        XCTAssertNil(reassembler.receive(.init(id: id, index: 1, total: 3, data: "90123")))
        // 丢弃后旧块不能复活：仅补 1、2 凑不齐，重发 0 后才完整
        XCTAssertNil(reassembler.receive(.init(id: id, index: 1, total: 3, data: "b")))
        XCTAssertNil(reassembler.receive(.init(id: id, index: 2, total: 3, data: "c")))
        XCTAssertEqual(reassembler.receive(.init(id: id, index: 0, total: 3, data: "a")), "abc")
    }

    func testReassemblerExpiresStaleEntries() {
        let reassembler = ChunkReassembler(ttl: 10)
        let id = UUID()
        let t0 = Date()
        XCTAssertNil(reassembler.receive(.init(id: id, index: 0, total: 2, data: "a"), now: t0))
        // 11s 后第二块到达：第一块半成品已过期被清理 → 凑不齐（若未清理这里会返回 "ab"）
        XCTAssertNil(reassembler.receive(.init(id: id, index: 1, total: 2, data: "b"),
                                         now: t0.addingTimeInterval(11)))
        // 第二块在 ttl 内补上第一块 → 成功
        XCTAssertEqual(reassembler.receive(.init(id: id, index: 0, total: 2, data: "a"),
                                           now: t0.addingTimeInterval(12)), "ab")
    }

    func testReassemblerRejectsWhenMaxEntriesExceeded() {
        // 33 个不同 id 各发一块(total=2 让它们停留在半成品)；第 33 个开头应被拒绝，后续凑齐也不重组。
        let reassembler = ChunkReassembler(maxEntries: 32)
        var ids: [UUID] = []
        for _ in 0..<32 {
            let id = UUID()
            ids.append(id)
            XCTAssertNil(reassembler.receive(.init(id: id, index: 0, total: 2, data: "a")))
        }
        // 第 33 个：新 id，entries 已满，应被拒绝
        let overflow = UUID()
        XCTAssertNil(reassembler.receive(.init(id: overflow, index: 0, total: 2, data: "x")))
        // 补齐第 33 个的第二块也应拿不到结果（因为 index 0 从未被接受）
        XCTAssertNil(reassembler.receive(.init(id: overflow, index: 1, total: 2, data: "y")))
    }

    func testInterleavedPayloadsDoNotInterfere() {
        let reassembler = ChunkReassembler()
        let first = ChunkedTransport.split("AAAA-BBBB-CCCC", limit: 5)
        let second = ChunkedTransport.split("111112222233333", limit: 5)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(second.count, 3)
        var results: [String] = []
        for (a, b) in zip(first, second) {
            if let done = reassembler.receive(a) { results.append(done) }
            if let done = reassembler.receive(b) { results.append(done) }
        }
        XCTAssertEqual(results, ["AAAA-BBBB-CCCC", "111112222233333"])
    }
}
