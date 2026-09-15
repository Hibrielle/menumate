import SwiftUI
import AppKit
import MenuMateCore

struct ExecutionLogView: View {
    @ObservedObject private var log = ExecutionLog.shared
    @State private var query = ""
    @State private var filter = ExecutionResultFilter.all
    @State private var confirmClear = false

    private var visible: [ExecutionRecord] {
        log.records.filter { filter.matches($0) && $0.matches(query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MMColor.label2)
                    TextField(String(localized: "execLog.search"), text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel(String(localized: "menu.clearSearch"))
                    }
                }
                .padding(8).background(MMColor.field, in: RoundedRectangle(cornerRadius: 6))
                Picker(String(localized: "execLog.filter"), selection: $filter) {
                    Text(String(localized: "execLog.all")).tag(ExecutionResultFilter.all)
                    Text(String(localized: "execLog.failed")).tag(ExecutionResultFilter.failed)
                    Text(String(localized: "execLog.succeeded")).tag(ExecutionResultFilter.succeeded)
                }.pickerStyle(.segmented).labelsHidden()
            }.padding(14)
            if let error = log.storageError {
                Banner(error, tone: .red).padding(.horizontal, 14).padding(.bottom, 10)
            }
            if visible.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: log.records.isEmpty ? "clock" : "magnifyingglass").font(.title2)
                    Text(String(localized: log.records.isEmpty ? "execLog.empty" : "execLog.noMatches"))
                    if !log.records.isEmpty {
                        Button(String(localized: "execLog.resetFilters")) { query = ""; filter = .all }
                    }
                }
                .font(.system(size: 12)).foregroundStyle(MMColor.label2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { RunRow(record: $0) }
                    }
                }
            }
            MMActionBar(horizontalPadding: 14) {
                HStack {
                    Text(String(format: String(localized: "execLog.showingCount"), visible.count, log.records.count))
                        .font(.system(size: 11)).foregroundStyle(MMColor.label2)
                        .help(String(localized: "execLog.retentionNote"))
                    Spacer(minLength: 8)
                    MMButton(String(localized: "execLog.clear"), kind: .plain, size: .sm) { confirmClear = true }
                        .disabled(log.records.isEmpty && log.storageError == nil)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 380)
        .background(MMColor.content)
        .alert(String(localized: "execLog.clearTitle"), isPresented: $confirmClear) {
            Button(String(localized: "execLog.clearConfirm"), role: .destructive) { log.clear() }
            Button(String(localized: "editor.cancel"), role: .cancel) {}
        } message: { Text(String(localized: "execLog.clearMessage")) }
    }
}

private struct RunRow: View {
    let record: ExecutionRecord
    @State private var expanded = false
    @State private var copied = false

    private var resultLabel: String {
        String(localized: record.timedOut == true ? "execLog.timedOut" : record.success ? "execLog.succeeded" : "execLog.failed")
    }
    private var resultColor: Color { record.success ? MMColor.green : MMColor.red }
    private var timestamp: String {
        record.date.formatted(date: .abbreviated, time: .standard)
    }
    private var durationLabel: String? {
        record.duration.map { String(format: String(localized: "execLog.duration"), $0) }
    }
    private var metadata: String {
        [resultLabel, timestamp, durationLabel].compactMap { $0 }.joined(separator: " · ")
    }
    private var copyText: String {
        var lines = [record.title, metadata]
        if let code = record.exitCode { lines.append("exit \(code)") }
        if let variant = record.variant, !variant.isEmpty { lines.append("variant: \(variant)") }
        lines += record.paths ?? []
        if let detail = record.detail { lines.append(detail) }
        if let output = record.stdout, !output.isEmpty { lines += ["stdout:", output] }
        if let output = record.stderr, !output.isEmpty { lines += ["stderr:", output] }
        if record.outputTruncated == true { lines.append(String(localized: "execLog.outputTruncated")) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: record.timedOut == true ? "clock.badge.exclamationmark" : record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(resultColor)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MMColor.label).lineLimit(2)
                        Text(metadata).font(.system(size: 10.5)).foregroundStyle(MMColor.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = record.detail, !detail.isEmpty {
                            Text(detail).font(.system(size: 11))
                                .foregroundStyle(record.success ? MMColor.label2 : MMColor.red)
                                .lineLimit(expanded ? 3 : 1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10)).foregroundStyle(MMColor.label2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let code = record.exitCode {
                        Text(String(format: String(localized: "execLog.exitCode"), Int(code)))
                            .font(.system(size: 11)).foregroundStyle(MMColor.label2)
                    }
                    if let variant = record.variant, !variant.isEmpty {
                        Text(String(format: String(localized: "execLog.variant"), variant))
                            .font(.system(size: 11)).textSelection(.enabled)
                    }
                    if let paths = record.paths, !paths.isEmpty {
                        Text(String(format: String(localized: "execLog.pathsCount"), paths.count, record.selectionCount ?? paths.count))
                            .font(.system(size: 11, weight: .medium))
                        Text(paths.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    output(record.stdout, title: String(localized: "execLog.stdout"))
                    output(record.stderr, title: String(localized: "execLog.stderr"))
                    if record.stdout == nil && record.stderr == nil {
                        output(record.detail, title: String(localized: "execLog.details"))
                    }
                    if record.outputTruncated == true {
                        Text(String(localized: "execLog.outputTruncated")).font(.system(size: 11)).foregroundStyle(MMColor.label2)
                    }
                    MMButton(String(localized: copied ? "execLog.copied" : "execLog.copyDetails"), systemImage: "doc.on.doc", size: .sm) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                        copied = true
                    }
                }.padding(.leading, 24)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .overlay(alignment: .top) { Rectangle().fill(MMColor.separator).frame(height: 0.5) }
    }

    @ViewBuilder private func output(_ text: String?, title: String) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                ScrollView {
                    Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 150)
            }
            .padding(10).background(MMColor.field, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
