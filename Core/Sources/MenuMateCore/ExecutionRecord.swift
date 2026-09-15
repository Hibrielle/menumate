import Foundation

/// New fields remain optional so existing execution-log.json files still decode.
public struct ExecutionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let success: Bool
    public let detail: String?
    public let duration: TimeInterval?
    public let exitCode: Int32?
    public let timedOut: Bool?
    public let stdout: String?
    public let stderr: String?
    public let paths: [String]?
    public let selectionCount: Int?
    public let variant: String?
    public let outputTruncated: Bool?

    public init(title: String, paths: [String], variant: String?, result: ShellResult,
                duration: TimeInterval, date: Date = Date()) {
        id = UUID(); self.date = date; self.title = title
        success = result.exitCode == 0 && !result.timedOut
        let summary = success ? result.stdout : (result.stderr.isEmpty ? result.stdout : result.stderr)
        detail = summary.split(separator: "\n").first.map { String($0.prefix(500)) }
        self.duration = max(0, duration)
        exitCode = result.exitCode; timedOut = result.timedOut
        stdout = String(result.stdout.prefix(16_000)); stderr = String(result.stderr.prefix(16_000))
        self.paths = Array(paths.prefix(20)); selectionCount = paths.count
        self.variant = variant
        outputTruncated = result.stdout.count > 16_000 || result.stderr.count > 16_000
    }

    public func matches(query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([title, detail ?? "", stdout ?? "", stderr ?? "", variant ?? ""] + (paths ?? []))
            .contains { $0.localizedStandardContains(query) }
    }
}

public enum ExecutionResultFilter: CaseIterable, Sendable {
    case all, failed, succeeded
    public func matches(_ record: ExecutionRecord) -> Bool {
        switch self {
        case .all: return true
        case .failed: return !record.success
        case .succeeded: return record.success
        }
    }
}

public struct ExecutionLogStore {
    public static let capacity = 50
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("execution-log.json") }
    public func load() throws -> [ExecutionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return Array(try JSONDecoder().decode([ExecutionRecord].self, from: Data(contentsOf: fileURL)).prefix(Self.capacity))
    }
    public func save(_ records: [ExecutionRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(records.prefix(Self.capacity))).write(to: fileURL, options: .atomic)
    }
}
