import Foundation
import Darwin

/// Serializes MenuMate's config writes and pack transactions across app processes.
enum StorageLock {
    static func perform<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appendingPathComponent(".storage.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

/// A recoverable transaction spanning a pack directory, installed.json and config.json.
/// A prepared journal always rolls back; a committed journal only needs cleanup.
/// Checkpoints allow tests to inject I/O errors or terminate a separate process.
public final class PackTransaction {
    public enum Step: String, CaseIterable {
        case prepared, oldPackMoved, newPackMoved, installedWritten, configWritten, committed
        case rollbackPackRestored, rollbackInstalledRestored, rollbackConfigRestored
    }
    public enum Failure: LocalizedError {
        case invalidJournal, invalidKey, pendingRecovery, configurationChanged
        public var errorDescription: String? {
            switch self {
            case .invalidJournal: return String(localized: "storage.invalidJournal", bundle: .module)
            case .invalidKey: return String(localized: "storage.invalidPackKey", bundle: .module)
            case .pendingRecovery: return String(localized: "storage.pendingRecovery", bundle: .module)
            case .configurationChanged: return String(localized: "storage.configurationChanged", bundle: .module)
            }
        }
    }
    private struct Journal: Codable {
        var version = 1
        var key: String
        var oldConfig: Data?
        var oldInstalled: Data?
        var hadPack: Bool
        var oldPackInode: UInt64?
        var committed = false
    }
    public let directory: URL
    private let checkpoint: (Step) throws -> Void
    private let fm = FileManager.default
    private var transaction: URL { directory.appendingPathComponent(".pack-transaction", isDirectory: true) }
    private var journalURL: URL { transaction.appendingPathComponent("journal.json") }
    private var packs: URL { directory.appendingPathComponent("Packs", isDirectory: true) }
    private var configURL: URL { directory.appendingPathComponent("config.json") }
    private var installedURL: URL { packs.appendingPathComponent("installed.json") }
    public var needsRecovery: Bool { exists(transaction) }

    public init(directory: URL, checkpoint: @escaping (Step) throws -> Void = { _ in }) {
        self.directory = directory
        self.checkpoint = checkpoint
    }

    /// Call before loading configuration or publishing a Finder snapshot on startup.
    @discardableResult public func recover() throws -> Bool {
        try StorageLock.perform(in: directory) { try recoverLocked() }
    }

    public func apply(key: String, replacement: URL?, config: MenuConfig,
                      installed: Data, expectedConfig: MenuConfig, expectedInstalled: Data?) throws {
        try StorageLock.perform(in: directory) {
            // Do not recover behind a caller's already-built candidate configuration.
            guard !needsRecovery else { throw Failure.pendingRecovery }
            guard Self.valid(key) else { throw Failure.invalidKey }
            let oldConfig = try optionalData(configURL)
            let onDisk = try oldConfig.map { try JSONDecoder().decode(MenuConfig.self, from: $0) } ?? .defaultSeed()
            guard onDisk == expectedConfig else { throw Failure.configurationChanged }
            let oldInstalled = try optionalData(installedURL)
            guard oldInstalled == expectedInstalled else { throw Failure.configurationChanged }
            let destination = packs.appendingPathComponent(key, isDirectory: true)
            if exists(destination) {
                let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalidKey }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let newConfig = try encoder.encode(config)
            var journal = Journal(key: key, oldConfig: oldConfig, oldInstalled: oldInstalled,
                                  hadPack: exists(destination), oldPackInode: inode(destination))
            try fm.createDirectory(at: packs, withIntermediateDirectories: true)
            try fm.createDirectory(at: transaction, withIntermediateDirectories: false)
            do {
                // Copy to the same volume first. Interrupted staging has no effect on live files.
                if let replacement { try fm.copyItem(at: replacement, to: transaction.appendingPathComponent("new-pack")) }
                try writeJournal(journal)
                try checkpoint(.prepared)
                if journal.hadPack {
                    try fm.moveItem(at: destination, to: transaction.appendingPathComponent("old-pack"))
                }
                try checkpoint(.oldPackMoved)
                if replacement != nil {
                    try fm.moveItem(at: transaction.appendingPathComponent("new-pack"), to: destination)
                }
                try checkpoint(.newPackMoved)
                try installed.write(to: installedURL, options: .atomic)
                try checkpoint(.installedWritten)
                try newConfig.write(to: configURL, options: .atomic)
                try checkpoint(.configWritten)
                journal.committed = true
                try writeJournal(journal)
            } catch {
                let original = error
                // If rollback fails, retain the journal/backups and require recovery before any writes.
                try recoverLocked()
                throw original
            }
            // The commit marker is the point of no return. A cleanup error must not report failure
            // (or roll back a committed operation); the next launch retries cleanup.
            try? checkpoint(.committed)
            try? finish()
        }
    }

    @discardableResult private func recoverLocked() throws -> Bool {
        cleanupGarbage()
        guard needsRecovery else { return false }
        let values = try transaction.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.invalidJournal }
        guard fm.fileExists(atPath: journalURL.path) else {
            // No journal can only be an interrupted copy before live files were touched.
            // An old-pack without a journal is not a valid staging directory; preserve it for repair.
            guard !fm.fileExists(atPath: transaction.appendingPathComponent("old-pack").path) else { throw Failure.invalidJournal }
            try finish()
            return true
        }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
        guard journal.version == 1, Self.valid(journal.key) else { throw Failure.invalidJournal }
        if !journal.committed {
            let destination = packs.appendingPathComponent(journal.key, isDirectory: true)
            let backup = transaction.appendingPathComponent("old-pack", isDirectory: true)
            if fm.fileExists(atPath: backup.path) {
                try removeIfPresent(destination)
                try fm.moveItem(at: backup, to: destination)
            } else if !journal.hadPack {
                try removeIfPresent(destination)
            } else {
                guard let original = journal.oldPackInode, inode(destination) == original else {
                    throw Failure.invalidJournal
                }
            }
            // If hadPack is true with no backup, either the first rename never happened or
            // a previous recovery already restored it. Both cases must leave destination alone.
            try checkpoint(.rollbackPackRestored)
            try restore(journal.oldInstalled, to: installedURL)
            try checkpoint(.rollbackInstalledRestored)
            try restore(journal.oldConfig, to: configURL)
            try checkpoint(.rollbackConfigRestored)
        }
        try finish()
        return true
    }

    private func exists(_ url: URL) -> Bool { inode(url) != nil }
    private func inode(_ url: URL) -> UInt64? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? UInt64(info.st_ino) : nil
    }
    private func cleanupGarbage() {
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(".pack-cleanup-") {
            guard UUID(uuidString: String(entry.lastPathComponent.dropFirst(".pack-cleanup-".count))) != nil else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    private func finish() throws {
        // Remove the active journal atomically before recursive cleanup. An interrupted cleanup
        // must never turn a committed transaction into an apparently unprepared transaction.
        let garbage = directory.appendingPathComponent(".pack-cleanup-" + UUID().uuidString)
        try fm.moveItem(at: transaction, to: garbage)
        try? fm.removeItem(at: garbage)
    }

    private static func valid(_ key: String) -> Bool {
        !key.isEmpty && !key.hasPrefix(".") && !key.contains("/") && !key.contains("\\") && key != "installed.json"
    }
    private func optionalData(_ url: URL) throws -> Data? {
        guard exists(url) else { return nil }
        return try Data(contentsOf: url)
    }
    private func writeJournal(_ journal: Journal) throws {
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }
    private func removeIfPresent(_ url: URL) throws {
        // resourceValues sees a dangling symlink, unlike fileExists.
        if exists(url) { try fm.removeItem(at: url) }
    }
    private func restore(_ data: Data?, to url: URL) throws {
        if try optionalData(url) == data { return }
        if let data { try data.write(to: url, options: .atomic) }
        else { try removeIfPresent(url) }
    }
}
