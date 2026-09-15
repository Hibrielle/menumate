import Foundation
import MenuMateCore

@MainActor
final class ExecutionLog: ObservableObject {
    static let shared = ExecutionLog()
    @Published private(set) var records: [ExecutionRecord] = []
    @Published private(set) var storageError: String?
    private let store: ExecutionLogStore
    private var unreadableHistory = false

    init(directory: URL = AppPaths.configDirectory()) {
        store = ExecutionLogStore(directory: directory)
        do { records = try store.load() }
        catch {
            unreadableHistory = true
            storageError = String(format: String(localized: "execLog.loadError"), error.localizedDescription)
        }
    }

    func append(_ record: ExecutionRecord) {
        records = Array(([record] + records).prefix(ExecutionLogStore.capacity))
        // Keep new results visible without overwriting an unreadable history file.
        guard !unreadableHistory else { return }
        do { try store.save(records); storageError = nil }
        catch { storageError = String(format: String(localized: "execLog.saveError"), error.localizedDescription) }
    }

    func clear() {
        do {
            try store.save([])
            records = []; storageError = nil; unreadableHistory = false
        } catch { storageError = String(format: String(localized: "execLog.saveError"), error.localizedDescription) }
    }
}
