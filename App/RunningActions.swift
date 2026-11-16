import Foundation

/// 正在排队或执行中的真实动作(不含试运行),供菜单栏显示「正在执行」。
@MainActor
final class RunningActions: ObservableObject {
    static let shared = RunningActions()

    struct Entry: Identifiable {
        let id = UUID()
        let title: String
        var startedAt: Date?   // nil = 还在串行队列里排队
    }

    @Published private(set) var entries: [Entry] = []

    func enqueue(title: String) -> UUID {
        let entry = Entry(title: title)
        entries.append(entry)
        return entry.id
    }

    func markStarted(_ id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].startedAt = Date()
    }

    func finish(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
