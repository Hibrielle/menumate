import Foundation
import MenuMateCore
import Darwin

@main struct StorageIntegration {
    static func require(_ value: Bool) { precondition(value) }
    enum Injected: Error { case failure }
    static let fm = FileManager.default
    static let key = "fixture"
    static let manifest = PackManifest(schemaVersion: 1, name: "New pack", actions: [PackAction(id: "action", title: "New action", script: "action.sh")])
    @MainActor static func action(root: URL, title: String) -> MenuAction {
        MenuAction(id: PackManager.actionUUID(packKey: key, packActionID: "action"), title: title,
            icon: .symbol("bolt"), kind: .runScript(ScriptSpec(scriptPath: root.appendingPathComponent("Packs/fixture/action.sh").path)),
            matching: MatchRule(), placement: .topLevel, packID: key, isEnabled: true, sortOrder: 0)
    }
    @MainActor static func setup(_ root: URL, operation: String) throws {
        AppPaths.root = root
        let configRoot = AppPaths.configDirectory()
        try fm.createDirectory(at: configRoot.appendingPathComponent("Packs"), withIntermediateDirectories: true)
        let installed = operation != "import"
        let initial = MenuConfig(schemaVersion: 1, actions: installed ? [action(root: configRoot, title: "Old action")] : [])
        try ConfigStore(directory: configRoot).save(initial)
        let records = installed ? [PackManager.InstalledRecord(key: key, repoURL: "local", repo: "fixture",
            commitSHA: "old", manifest: PackManifest(schemaVersion: 1, name: "Old pack", actions: [PackAction(id: "action", title: "Old action", script: "action.sh")]))] : []
        try JSONEncoder().encode(records).write(to: configRoot.appendingPathComponent("Packs/installed.json"))
        if installed {
            try fm.createDirectory(at: configRoot.appendingPathComponent("Packs/fixture"), withIntermediateDirectories: true)
            try Data("old script".utf8).write(to: configRoot.appendingPathComponent("Packs/fixture/action.sh"))
        }
        let source = root.appendingPathComponent("reviewed")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("new script".utf8).write(to: source.appendingPathComponent("action.sh"))
    }
    @MainActor static func perform(_ operation: String, state: AppState) throws {
        let source = AppPaths.root.appendingPathComponent("reviewed")
        switch operation {
        case "import":
            try state.packManager.confirmImport(ClonedPack(tempDir: source, key: key, manifest: manifest,
                repoURL: "local", repo: "fixture", commitSHA: "new", scripts: [:]))
        case "update":
            try state.packManager.applyUpdate(key, PackUpdate(key: key, baseSHA: "old", tempDir: source, newManifest: manifest,
                newSHA: "new", newRepoURL: "local", newRepo: "fixture", diffsByFile: [], newScripts: [:]))
        default: try state.packManager.uninstall(key)
        }
    }
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 4 {
            let step = PackTransaction.Step(rawValue: CommandLine.arguments[2])!
            let tx = PackTransaction(directory: AppPaths.configDirectory()) { reached in
                if reached == step { _exit(77) }
                if step.rawValue.hasPrefix("rollback"), reached == .configWritten { throw Injected.failure }
            }
            let state = AppState(transaction: tx)
            state.reloadFromDisk()
            try perform(CommandLine.arguments[3], state: state)
            fatalError("Crash checkpoint was not reached")
        }
        let root = AppPaths.root
        defer { try? fm.removeItem(at: root) }
        try setup(root, operation: "update")
        let state = AppState()
        state.reloadFromDisk()
        let old = state.config
        let oldBytes = try Data(contentsOf: state.store.fileURL)
        let posts = DistributedNotificationCenter.default().posts
        let prunes = IconStore.pruneCount
        // Real filesystem denial: locks can open, but an atomic replacement cannot be created.
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: AppPaths.configDirectory().path)
        let result = state.mutateConfig { $0.actions[0].title = "Must not publish" }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: AppPaths.configDirectory().path)
        precondition(!result && state.config == old && state.configError != nil)
        precondition(DistributedNotificationCenter.default().posts == posts && IconStore.pruneCount == prunes)
        require(try Data(contentsOf: state.store.fileURL) == oldBytes)
        precondition(state.mutateConfig { $0.actions[0].title = "Saved" })
        require(try state.store.load(fresh: true) == state.config && state.configError == nil)
        print("PASS denied config write: no published edit, no snapshot, no icon cleanup; retry succeeds")

        try Data("broken config".utf8).write(to: state.store.fileURL)
        let corrupt = AppState()
        let beforePrune = IconStore.pruneCount
        corrupt.start()
        precondition(corrupt.config.actions.isEmpty && corrupt.configError != nil && IconStore.pruneCount == beforePrune)
        precondition(!corrupt.update(old))
        require(try String(contentsOf: state.store.fileURL) == "broken config")
        print("PASS corrupt startup config preserved; no seed actions or icon cleanup; writes rejected")

        // Execute the production manager, terminate at every write/rollback boundary, then start
        // a fresh production AppState against those exact on-disk files.
        var count = 0
        for operation in ["import", "update", "uninstall"] {
            for step in PackTransaction.Step.allCases {
                let runRoot = root.appendingPathComponent(operation + "-" + step.rawValue)
                try setup(runRoot, operation: operation)
                let dir = AppPaths.configDirectory()
                let oldConfig = try Data(contentsOf: dir.appendingPathComponent("config.json"))
                let oldRegistry = try Data(contentsOf: dir.appendingPathComponent("Packs/installed.json"))
                let process = Process()
                process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                process.arguments = ["--crash", step.rawValue, operation]
                process.environment = ProcessInfo.processInfo.environment.merging(["MENUMATE_TEST_ROOT": runRoot.path]) { _, new in new }
                try process.run(); process.waitUntilExit()
                precondition(process.terminationStatus == 77, "Checkpoint \(operation)/\(step) not reached")
                let recovered = AppState()
                recovered.start()
                precondition(!recovered.storageRecoveryRequired && recovered.configError == nil)
                let script = dir.appendingPathComponent("Packs/fixture/action.sh")
                if step == .committed {
                    if operation == "uninstall" {
                        precondition(recovered.config.actions.isEmpty && !fm.fileExists(atPath: script.path))
                    } else {
                        require(try String(contentsOf: script) == "new script")
                        precondition(recovered.packManager.packs.first?.commitSHA == "new")
                        precondition(recovered.config.actions.count == 1)
                    }
                } else {
                    require(try Data(contentsOf: dir.appendingPathComponent("config.json")) == oldConfig)
                    require(try Data(contentsOf: dir.appendingPathComponent("Packs/installed.json")) == oldRegistry)
                    if operation == "import" { precondition(!fm.fileExists(atPath: script.path)) }
                    else { require(try String(contentsOf: script) == "old script") }
                }
                precondition(!recovered.packTransaction.needsRecovery)
                require(!(try recovered.packTransaction.recover())) // second recovery is harmless
                count += 1
            }
        }
        print("PASS \(count) process interruptions: import/update/uninstall and interrupted rollback; startup recovery is idempotent")

        let recoveryRoot = root.appendingPathComponent("recovery-failure")
        try setup(recoveryRoot, operation: "update")
        let failingTransaction = PackTransaction(directory: AppPaths.configDirectory()) {
            if $0 == .configWritten || $0 == .rollbackPackRestored { throw Injected.failure }
        }
        let failedRecovery = AppState(transaction: failingTransaction)
        failedRecovery.reloadFromDisk()
        let lastSaved = failedRecovery.config
        do { try perform("update", state: failedRecovery); preconditionFailure("Expected rollback failure") } catch {}
        precondition(failedRecovery.storageRecoveryRequired && failedRecovery.config == lastSaved)
        precondition(!failedRecovery.mutateConfig { $0.actions.removeAll() })
        precondition(failedRecovery.packTransaction.needsRecovery)
        let restarted = AppState()
        restarted.start()
        precondition(!restarted.storageRecoveryRequired && restarted.config == lastSaved)
        precondition(restarted.configError == nil)
        print("PASS failed rollback pauses actions/writes and retains backups; fresh startup recovers")

        let busyRoot = root.appendingPathComponent("busy")
        try setup(busyRoot, operation: "update")
        let busy = AppState(); busy.reloadFromDisk()
        PackUsage.retain(key)
        do { try perform("update", state: busy); preconditionFailure("busy pack updated") } catch PackManager.PackError.busy {}
        do { try perform("uninstall", state: busy); preconditionFailure("busy pack uninstalled") } catch PackManager.PackError.busy {}
        PackUsage.release(key)
        let registry = AppPaths.configDirectory().appendingPathComponent("Packs/installed.json")
        try Data("broken registry".utf8).write(to: registry)
        do { try perform("update", state: busy); preconditionFailure("corrupt registry overwritten") } catch {}
        require(try String(contentsOf: registry) == "broken registry")
        print("PASS busy pack update/uninstall rejected; corrupt installed registry preserved")
    }
}
