import Foundation
import MenuMateCore

enum ExecutionOutcome {
    case success(summary: String?)
    case failure(message: String)
}

struct ExecutionRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let success: Bool
    let detail: String?
}

@MainActor
final class ExecutionLog: ObservableObject {
    static let shared = ExecutionLog()
    @Published private(set) var records: [ExecutionRecord] = []
    private let fileURL = AppPaths.configDirectory().appendingPathComponent("execution-log.json")
    private let cap = 50

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([ExecutionRecord].self, from: data) {
            records = loaded
        }
    }

    func append(title: String, outcome: ExecutionOutcome) {
        let record: ExecutionRecord
        switch outcome {
        case .success(let summary):
            record = ExecutionRecord(id: UUID(), date: Date(), title: title, success: true,
                                     detail: summary.map { String($0.prefix(500)) })
        case .failure(let message):
            record = ExecutionRecord(id: UUID(), date: Date(), title: title, success: false,
                                     detail: String(message.prefix(500)))
        }
        records = Array(([record] + records).prefix(cap))
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: fileURL, options: .atomic) }
    }

    func clear() {
        records = []
        try? FileManager.default.removeItem(at: fileURL)
    }
}
