import Foundation
import CryptoKit

public struct PackFileDiff: Equatable, Sendable {
    public let path: String
    public let oldText: String?
    public let newText: String?
    public var isAdded: Bool { oldText == nil && newText != nil }
    public var isRemoved: Bool { oldText != nil && newText == nil }
    public var isModified: Bool { oldText != nil && newText != nil && oldText != newText }
    public var isUnchanged: Bool { oldText == newText }
}

/// Review the entire installed tree, not just entrypoints listed in the manifest.
/// Snapshot errors abort the update rather than pretending an unreadable file is unchanged.
public enum PackDirectoryDiff {
    private static let maximumPreviewBytes = 262_144
    private static let maximumEntries = 10_000

    public static func compare(old: URL, new: URL) throws -> [PackFileDiff] {
        let before = try snapshot(old), after = try snapshot(new)
        return Set(before.keys).union(after.keys).sorted().map {
            PackFileDiff(path: $0, oldText: before[$0], newText: after[$0])
        }
    }

    private static func snapshot(_ directory: URL) throws -> [String: String] {
        let fm = FileManager.default
        let root = directory.resolvingSymlinksInPath()
        // Enumerate relative names ourselves: standardizing entry URLs can resolve
        // symbolic links, which would hide the link or inspect an external target.
        var pending = try fm.contentsOfDirectory(atPath: root.path).filter { $0 != ".git" }
        var result: [String: String] = [:]
        var previewBytes = 0
        while let relative = pending.popLast() {
            guard result.count < maximumEntries else {
                throw CocoaError(.fileReadTooLarge, userInfo: [NSFilePathErrorKey: root.path])
            }
            let file = root.appendingPathComponent(relative)
            let attributes = try fm.attributesOfItem(atPath: file.path)
            let kind = attributes[.type] as? FileAttributeType
            let mode = String((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)
            switch kind {
            case .typeSymbolicLink:
                // Show the link itself; never open a target outside the reviewed tree.
                result[relative] = "symlink → " + (try fm.destinationOfSymbolicLink(atPath: file.path))
            case .typeDirectory:
                result[relative] = "directory · mode " + mode
                let children = try fm.contentsOfDirectory(atPath: file.path)
                pending.append(contentsOf: children.map { relative + "/" + $0 })
            case .typeRegular:
                result[relative] = try describeFile(file, mode: mode)
            default:
                throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: file.path])
            }
            previewBytes += result[relative]?.utf8.count ?? 0
            guard previewBytes <= 33_554_432 else {
                throw CocoaError(.fileReadTooLarge, userInfo: [NSFilePathErrorKey: root.path])
            }
        }
        return result
    }

    private static func describeFile(_ file: URL, mode: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var digest = SHA256(), preview = Data(), byteCount = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            digest.update(data: chunk)
            byteCount += chunk.count
            if byteCount <= maximumPreviewBytes { preview.append(chunk) }
        }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let summary = "mode \(mode) · \(byteCount) bytes · SHA-256 \(hash)"
        if byteCount <= maximumPreviewBytes, !preview.contains(0),
           let text = String(data: preview, encoding: .utf8) {
            return summary + "\n\n" + text
        }
        // Full content is hashed even when a binary or large file cannot be rendered.
        return summary
    }
}
