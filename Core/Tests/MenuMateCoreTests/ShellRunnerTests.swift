import XCTest
@testable import MenuMateCore

final class ShellRunnerTests: XCTestCase {
    func testHostileTimeoutValuesDoNotCrash() {
        let r1 = ShellRunner.run("/bin/echo", ["x"], timeout: -1)
        let r2 = ShellRunner.run("/bin/echo", ["x"], timeout: 99_999_999_999)
        XCTAssertEqual(r1.exitCode, 0)
        XCTAssertEqual(r2.exitCode, 0)
    }

    func testCapturesStdoutAndExitCode() {
        let r = ShellRunner.run("/bin/echo", ["hello"], timeout: 5)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertFalse(r.timedOut)
    }

    func testNonZeroExit() {
        let r = ShellRunner.run("/bin/zsh", ["-c", "echo err >&2; exit 3"], timeout: 5)
        XCTAssertEqual(r.exitCode, 3)
        XCTAssertTrue(r.stderr.contains("err"))
    }

    func testTimeoutKillsProcess() {
        let start = Date()
        let r = ShellRunner.run("/bin/sleep", ["30"], timeout: 1)
        XCTAssertTrue(r.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testRunScriptInlinePassesPathsAsArgvAndEnv() {
        let spec = ScriptSpec(inlineSource: #"printf '%s|%s|%s' "$1" "$2" "$MENUMATE_PATHS""#)
        let r = ShellRunner.runScript(spec, paths: ["/tmp/x", "/tmp/y z"], variant: nil,
                                      scriptBase: URL(fileURLWithPath: "/tmp"), cwd: nil)
        XCTAssertEqual(r.stdout, "/tmp/x|/tmp/y z|/tmp/x\n/tmp/y z")
    }

    func testRunScriptResolvesRelativePathAndInjectsVariantAndExtraEnv() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("Scripts"),
                                                withIntermediateDirectories: true)
        let script = base.appendingPathComponent("Scripts/t.sh")
        // 不设可执行位：约定外部脚本一律由 zsh 解释执行
        try #"printf '%s|%s|%s' "$MENUMATE_VARIANT" "$MENUMATE_DATA" "$1""#
            .write(to: script, atomically: true, encoding: .utf8)
        let r = ShellRunner.runScript(ScriptSpec(scriptPath: "Scripts/t.sh"),
                                      paths: ["/tmp/p"], variant: "png", scriptBase: base,
                                      cwd: nil, extraEnv: ["MENUMATE_DATA": "/data"])
        XCTAssertEqual(r.stdout, "png|/data|/tmp/p")
    }

    // MARK: - Regression tests for backgrounded-grandchild / stalled-drain bug

    /// A backgrounded grandchild (`sleep 30 &`) must NOT hold up run() return.
    /// Before the fix, the unbounded group.wait() would block until sleep 30 died.
    func testBackgroundedGrandchildDoesNotHangRun() {
        let start = Date()
        let r = ShellRunner.run("/bin/zsh", ["-c", "sleep 30 & echo done"], timeout: 10)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5,
                          "后台孙进程不得拖住 run() 返回")
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertTrue(r.stdout.contains("done"), "已捕获的输出必须保留")
        XCTAssertFalse(r.timedOut)
    }

    /// When timeout fires, the whole process group (including backgrounded descendants)
    /// must be killed — verified by probing the grandchild's PID after the fact.
    func testTimeoutKillsProcessGroup() throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pid").path
        let r = ShellRunner.run("/bin/zsh", ["-c", "sleep 30 & echo $! > \(pidFile); sleep 30"],
                                timeout: 1)
        XCTAssertTrue(r.timedOut)
        usleep(300_000)
        let gcpid = Int32(try String(contentsOfFile: pidFile)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        XCTAssertNotEqual(kill(gcpid, 0), 0, "孙进程应已被进程组击杀")
    }

    /// Large output must not deadlock (regression for pipe-buffer-full → writer blocks →
    /// reader waiting for process exit → deadlock).
    func testLargeOutputDoesNotDeadlock() {
        let r = ShellRunner.run("/bin/zsh", ["-c", "head -c 300000 /dev/zero | tr '\\0' x"],
                                timeout: 10)
        XCTAssertEqual(r.stdout.count, 300_000)
        XCTAssertEqual(r.exitCode, 0)
    }

    /// stdin must be closed (nullDevice) so a script that reads stdin gets immediate
    /// EOF rather than blocking until the timeout.
    func testStdinIsClosedSoReadDoesNotBlock() {
        let start = Date()
        let r = ShellRunner.run("/bin/zsh", ["-c", "read -r line; echo after"], timeout: 10)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertFalse(r.timedOut)
    }

    /// scriptPath wins over inlineSource when both are present.
    func testScriptPathWinsOverInlineSource() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let script = base.appendingPathComponent("s.sh")
        try "echo from-file".write(to: script, atomically: true, encoding: .utf8)
        let spec = ScriptSpec(scriptPath: script.path, inlineSource: "echo from-inline")
        let r = ShellRunner.runScript(spec, paths: [], variant: nil, scriptBase: base, cwd: nil)
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "from-file")
    }

    /// Contract env (MENUMATE_VARIANT etc.) must beat extraEnv — callers cannot
    /// accidentally clobber the execution-layer semantics.
    func testContractEnvBeatsExtraEnv() {
        let spec = ScriptSpec(inlineSource: #"printf '%s' "$MENUMATE_VARIANT""#)
        let r = ShellRunner.runScript(spec, paths: [], variant: "real",
                                      scriptBase: URL(fileURLWithPath: "/tmp"),
                                      cwd: nil, extraEnv: ["MENUMATE_VARIANT": "clobbered"])
        XCTAssertEqual(r.stdout, "real")
    }
}
