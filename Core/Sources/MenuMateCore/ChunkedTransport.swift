import Foundation

/// 跨进程载荷的分块传输协议（经 DistributedNotificationCenter，object 字符串）。
/// 取代 app-group sidecar 文件：任何尺寸载荷都拆成 ≤chunkLimit 字节的块逐条发送。
public enum ChunkedTransport {
    /// 单块数据的 UTF-8 字节预算。
    /// 数据子串二次 JSON 转义最坏膨胀 2×（"/\ 密集），chunkLimit×2+信封 <64KB 接收闸，对一切密度安全。
    /// JSON 信封固定开销约 75B（UUID+index+total 字段），故上限 = (65536-75)/2 ≈ 32730；
    /// 取整保守为 32KB-512 = 32256，留足余量。
    public static let chunkLimit = 32 * 1024 - 512

    public struct Chunk: Codable, Equatable {
        public var id: UUID          // 同一载荷的所有块共享
        public var index: Int        // 0-based
        public var total: Int
        public var data: String      // 载荷的连续子串（按字符边界切，字节数 ≤ limit）

        public init(id: UUID, index: Int, total: Int, data: String) {
            self.id = id; self.index = index; self.total = total; self.data = data
        }

        public func encodedString() throws -> String {
            let encoder = JSONEncoder()
            // 不转义 /：载荷多为路径密集 JSON，转义会让信封膨胀逼近接收端 64KB 闸门
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        }

        public static func decode(_ s: String) throws -> Chunk {
            try JSONDecoder().decode(Chunk.self, from: Data(s.utf8))
        }
    }

    /// 按 UTF-8 字节预算、字符边界切分。空载荷 → 1 个空块。
    public static func split(_ payload: String, limit: Int = chunkLimit) -> [Chunk] {
        var pieces: [String] = []
        var current = ""
        var currentBytes = 0
        for character in payload {
            let bytes = character.utf8.count
            if currentBytes + bytes > limit, !current.isEmpty {
                pieces.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += bytes
        }
        if !current.isEmpty || pieces.isEmpty { pieces.append(current) }
        let id = UUID()
        return pieces.enumerated().map {
            Chunk(id: id, index: $0.offset, total: pieces.count, data: $0.element)
        }
    }
}

/// 接收端重组器（单线程使用；有 DoS 上界与过期清理）。
public final class ChunkReassembler {
    private struct Entry {
        var total: Int
        var parts: [Int: String]
        var bytes: Int
        var lastUpdate: Date
    }

    private var entries: [UUID: Entry] = [:]
    private let maxTotalBytes: Int
    private let maxChunks: Int
    private let ttl: TimeInterval
    private let maxEntries: Int

    public init(maxTotalBytes: Int = 4 * 1024 * 1024, maxChunks: Int = 256, ttl: TimeInterval = 10, maxEntries: Int = 32) {
        self.maxTotalBytes = maxTotalBytes
        self.maxChunks = maxChunks
        self.ttl = ttl
        self.maxEntries = maxEntries
    }

    /// 收到一块；凑齐返回完整载荷并清除该条目，否则返回 nil。
    /// 拒绝：total>maxChunks、index 越界、与已记录 total 不符（不挤掉合法半成品）、
    /// 累计字节超 maxTotalBytes（整条丢弃）。每次调用顺带清理超过 ttl 的半成品。
    public func receive(_ chunk: ChunkedTransport.Chunk, now: Date = Date()) -> String? {
        entries = entries.filter { now.timeIntervalSince($0.value.lastUpdate) <= ttl }

        guard chunk.total >= 1, chunk.total <= maxChunks,
              chunk.index >= 0, chunk.index < chunk.total else { return nil }

        // 新 id 且已满：先做一次 TTL 清理，仍满则拒绝
        if entries[chunk.id] == nil, entries.count >= maxEntries {
            entries = entries.filter { now.timeIntervalSince($0.value.lastUpdate) <= ttl }
            if entries.count >= maxEntries { return nil }
        }

        var entry = entries[chunk.id] ?? Entry(total: chunk.total, parts: [:], bytes: 0, lastUpdate: now)
        guard entry.total == chunk.total else { return nil }

        if let previous = entry.parts[chunk.index] { entry.bytes -= previous.utf8.count }
        entry.parts[chunk.index] = chunk.data
        entry.bytes += chunk.data.utf8.count
        entry.lastUpdate = now

        guard entry.bytes <= maxTotalBytes else {
            entries[chunk.id] = nil
            return nil
        }

        guard entry.parts.count == entry.total else {
            entries[chunk.id] = entry
            return nil
        }
        entries[chunk.id] = nil
        return (0..<entry.total).compactMap { entry.parts[$0] }.joined()
    }
}
