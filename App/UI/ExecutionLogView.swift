import SwiftUI

// 最近执行 — 对照 docs/design/hifi/screen-misc.jsx RecentRuns / RunRow(420×340)。
// 每行:✓ 绿(成功)/ ✗ 红(失败)+ 标题 12.5 + 右时间戳(等宽灰 HH:mm:ss);
// 失败且有 detail → 行下内联红底等宽 stderr。底栏:保留最近 50 条 + 清空。
struct ExecutionLogView: View {
    @ObservedObject private var log = ExecutionLog.shared

    var body: some View {
        VStack(spacing: 0) {
            if log.records.isEmpty {
                Spacer()
                Text(String(localized: "execLog.empty"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(MMColor.label3)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(log.records) { record in
                            RunRow(record: record)
                        }
                    }
                }
            }

            // 底栏。
            HStack {
                Text(String(localized: "execLog.retentionNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(MMColor.label3)
                Spacer()
                MMButton(String(localized: "execLog.clear"), kind: .plain, size: .sm) {
                    log.clear()
                }
                .disabled(log.records.isEmpty)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .overlay(alignment: .top) {
                Rectangle().fill(MMColor.separator).frame(height: 0.5)
            }
        }
        .frame(minWidth: 420, minHeight: 340)
        .background(MMColor.content)
    }
}

// 单条执行行。
private struct RunRow: View {
    let record: ExecutionRecord

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(record.success ? MMColor.green : MMColor.red)
                Text(record.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(MMColor.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.timeFormatter.string(from: record.date))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MMColor.label3)
            }
            // 失败且有 detail → 内联红底等宽 stderr。
            if !record.success, let detail = record.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(MMColor.red)
                    .lineSpacing(2.5) // ≈ line-height 1.5
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MMColor.red.opacity(MMColor.isDark ? 0.20 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: MMRadius.badge, style: .continuous))
                    .padding(.leading, 24)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(MMColor.separator.opacity(0.6)).frame(height: 0.5)
        }
    }
}
