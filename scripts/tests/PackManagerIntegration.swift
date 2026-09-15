@_exported import Combine
import Foundation
import MenuMateCore

@main struct PackManagerIntegration {
    @MainActor static func main() async throws {
        let fm = FileManager.default, root = AppPaths.root
        defer { try? fm.removeItem(at: root) }
        let repo = root.appendingPathComponent("remote")
        try fm.createDirectory(at: repo.appendingPathComponent("ui"), withIntermediateDirectories: true)
        try "print ok\n".write(to: repo.appendingPathComponent("a.zsh"), atomically: true, encoding: .utf8)
        try "<!doctype html><script src='options.js'></script>".write(to: repo.appendingPathComponent("ui/index.html"), atomically: true, encoding: .utf8)
        let js = repo.appendingPathComponent("ui/options.js")
        try "window.version=1;".write(to: js, atomically: true, encoding: .utf8)
        var manifest = PackManifest(schemaVersion: 2, name: "Test", actions: [
            PackAction(id: "a", title: "Default A", script: "a.zsh", interface: ActionInterface(entry: "ui/index.html"), localizedTitles: ["en": "English A", "zh-Hans": "中文 A"]),
            PackAction(id: "b", title: "Default B", script: "a.zsh")])
        func saveManifest() throws { try JSONEncoder().encode(manifest).write(to: repo.appendingPathComponent("manifest.json")) }
        func git(_ args: [String]) throws {
            let result = ShellRunner.run("/usr/bin/git", ["-c", "user.name=Tests", "-c", "user.email=tests@local", "-c", "commit.gpgsign=false"] + args, cwd: repo, timeout: 10)
            guard result.exitCode == 0 else { throw NSError(domain: result.stderr, code: Int(result.exitCode)) }
        }
        try saveManifest(); try git(["init", "-b", "main"]); try git(["add", "."]); try git(["commit", "-m", "initial"])
        try AppState.shared.store.save(MenuConfig(schemaVersion: 1, actions: []))
        AppState.shared.reloadFromDisk()
        let manager = AppState.shared.packManager
        let cloned = try await manager.clone(repo.path)
        try manager.confirmImport(cloned)
        precondition(AppState.shared.config.actions.count == 2)
        precondition(AppState.shared.config.actions[0].title(in: "en") == "English A")
        precondition(AppState.shared.config.actions.allSatisfy { !$0.isEnabled })
        let initialIDs = AppState.shared.config.actions.map(\.id)
        manager.setActionEnabled(true, actionID: initialIDs[0])
        AppState.shared.mutateConfig { config in
            config.actions[0].title = "User A"
            config.actions[0].localizedTitles = ["en": "Personal A"]
            config.actions[0].placement = .submenu
            config.actions[0].sortOrder = 10
        }
        let duplicate = try await manager.clone(repo.path)
        do { try manager.confirmImport(duplicate); preconditionFailure("Reimport must not overwrite installed actions") }
        catch PackManager.PackError.alreadyInstalled { manager.discard(tempDir: duplicate.tempDir) }
        precondition(AppState.shared.config.actions.map(\.id) == initialIDs)
        precondition(AppState.shared.config.actions[0].title == "User A")
        print("PASS import disabled, independent enable, duplicate rejected without overwriting")

        // Reproduce the original issue exactly: update only referenced JS.
        try "window.version=2;".write(to: js, atomically: true, encoding: .utf8)
        try git(["add", "."]); try git(["commit", "-m", "JS only"])
        let jsUpdate = try await manager.cloneUpdate(cloned.key)
        precondition(jsUpdate.diffsByFile.filter { !$0.isUnchanged }.map(\.path) == ["ui/options.js"])
        try manager.applyUpdate(cloned.key, jsUpdate)
        precondition(AppState.shared.config.actions[0].title == "User A")
        do { try manager.applyUpdate(cloned.key, jsUpdate); preconditionFailure("Stale reviewed update accepted") }
        catch PackTransaction.Failure.configurationChanged {}
        print("PASS JS-only update appears in review; stale reviewed revisions are rejected")

        manifest.actions[0].title = "Upstream A"
        manifest.actions[0].localizedTitles = ["en": "New English A", "zh-Hans": "新的中文 A"]
        manifest.actions[1].title = "Upstream B"
        manifest.actions.append(PackAction(id: "c", title: "New C", script: "a.zsh"))
        try saveManifest(); try git(["add", "."]); try git(["commit", "-m", "manifest"])
        let update = try await manager.cloneUpdate(cloned.key)
        precondition(update.diffsByFile.contains { $0.path == "manifest.json" && $0.isModified })
        try manager.applyUpdate(cloned.key, update)
        let actions = AppState.shared.config.actions
        precondition(actions.count == 3 && Set(actions.map(\.id)).count == 3)
        precondition(actions[0].title == "User A" && actions[0].placement == .submenu && actions[0].sortOrder == 10 && actions[0].isEnabled)
        precondition(actions[0].title(in: "en") == "Personal A")
        precondition(actions[0].title(in: "zh-Hans") == "User A")
        precondition(actions[1].title == "Upstream B" && actions[1].sortOrder == 1 && !actions[1].isEnabled)
        precondition(!actions[2].isEnabled && actions[2].sortOrder > 10)
        print("PASS preserve user overrides/order/enabled; accept upstream defaults; new actions disabled")
        try manager.uninstall(cloned.key)
        precondition(AppState.shared.config.actions.isEmpty)
        print("PASS whole-pack uninstall; isolated temporary data only")
    }
}
