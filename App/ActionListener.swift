import Foundation
import MenuMateCore

final class ActionListener {
    private let reassembler = ChunkReassembler()   // queue: .main 串行投递 → 单线程使用

    func start() {
        DistributedNotificationCenter.default().addObserver(
            // object: nil 有意为之——DNC 发送方不可信，防御靠块/总量上限+解码+派发闸门，切勿改成按 bundleID 过滤（可被伪造）
            forName: .init(IPC.actionNotification), object: nil, queue: .main) { [reassembler] note in
            guard let s = note.object as? String, s.utf8.count <= 64 * 1024,
                  let chunk = try? ChunkedTransport.Chunk.decode(s),
                  let payload = reassembler.receive(chunk),
                  let request = try? ActionRequest.decode(payload) else { return }
            Task { @MainActor in ActionDispatcher.shared.dispatch(request) }
        }
    }
}
