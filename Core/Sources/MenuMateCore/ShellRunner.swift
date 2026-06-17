import Foundation

public struct ShellResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

// MARK: - Thread-safe pipe buffer
// Allows the main thread to snapshot captured output while an abandoned reader
// may still be appending later (normal-exit + stalled-drain case).
private final class PipeBuffer {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    func snapshot() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

public enum ShellRunner {
    /// Run an executable and collect its output.
    ///
    /// **Timeout path**: SIGTERM → 200 ms grace → SIGKILL the whole process group
    /// (Foundation's Process makes the child a group leader; `getpgid(pid) == pid`).
    /// After killing, drain is bounded to ≤ 1 s; abandoned if still stuck.
    ///
    /// **Normal-exit + stalled-drain path** (backgrounded grandchild holds pipe
    /// write-end open): drain is bounded to 500 ms then abandoned.  The process
    /// group is NOT killed so intentional daemons survive.
    ///
    /// **Exit-code convention**: when the child died from an uncaught signal,
    /// `exitCode` is reported as `128 + signal_number` (POSIX shell convention).
    @discardableResult
    public static func run(_ executable: String, _ args: [String],
                           cwd: URL? = nil, extraEnv: [String: String] = [:],
                           timeout: TimeInterval = 60) -> ShellResult {
        // 超时钳制到 [0.1s, 24h]，防御配置中的非法值
        let timeout = max(0.1, min(timeout, 86_400))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        p.environment = ProcessInfo.processInfo.environment.merging(extraEnv) { _, new in new }

        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        // Close stdin immediately so any script that reads stdin gets EOF rather
        // than blocking until the timeout.
        p.standardInput = FileHandle.nullDevice

        let outBuf = PipeBuffer(), errBuf = PipeBuffer()

        // Use readabilityHandler (event-driven, non-blocking) so we capture
        // data as soon as it's written even while a grandchild keeps the
        // write-end alive.  readabilityHandler fires for each available chunk;
        // when availableData is empty the write-end has closed.
        let outDone = DispatchSemaphore(value: 0)
        let errDone = DispatchSemaphore(value: 0)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outDone.signal()
            } else {
                outBuf.append(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errDone.signal()
            } else {
                errBuf.append(chunk)
            }
        }

        do { try p.run() } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return ShellResult(exitCode: -1, stdout: "", stderr: "\(error)", timedOut: false)
        }

        // Use monotonic DispatchTime so wall-clock changes / system sleep don't
        // perturb the deadline.
        let deadlineNanos = DispatchTime.now().uptimeNanoseconds + UInt64(timeout * 1_000_000_000)
        var timedOut = false

        while p.isRunning {
            if DispatchTime.now().uptimeNanoseconds >= deadlineNanos {
                timedOut = true
                let pid = p.processIdentifier

                // Snapshot pgid BEFORE terminate() so the group ID is captured
                // while the process is still alive (avoids the reap race where
                // the child exits between terminate() and getpgid()).
                let pgid = getpgid(pid)

                // 1. Politely ask the direct child to stop.
                p.terminate()   // SIGTERM
                usleep(200_000) // 200 ms grace

                // 2. Kill the entire process group so backgrounded descendants
                //    (grandchildren) die too and the pipe write-ends close.
                //    Foundation makes the child a session/group leader, so
                //    pgid == pid.  Fall back to pid-only kill if that check fails.
                if pgid == pid {
                    kill(-pgid, SIGKILL)  // kill whole process group
                } else {
                    kill(pid, SIGKILL)    // fallback: kill direct child only
                }
                break
            }
            usleep(50_000)
        }

        p.waitUntilExit()

        // Bounded drain: after timeout give pipes at most 1 s; after normal exit
        // give at most 500 ms (handles backgrounded survivors holding write-end).
        let drainMs = timedOut ? 1000 : 500
        let drainDeadline = DispatchTime.now() + .milliseconds(drainMs)
        _ = outDone.wait(timeout: drainDeadline)
        _ = errDone.wait(timeout: drainDeadline)
        // If we timed out above, abandon the readers — they'll eventually fire when
        // grandchildren die.  We snapshot whatever is in the PipeBuffer right now.

        // Signal-death exit code normalization (128 + signal number).
        var exitCode = p.terminationStatus
        if p.terminationReason == .uncaughtSignal {
            exitCode = 128 + p.terminationStatus
        }

        return ShellResult(exitCode: exitCode,
                           stdout: String(decoding: outBuf.snapshot(), as: UTF8.self),
                           stderr: String(decoding: errBuf.snapshot(), as: UTF8.self),
                           timedOut: timedOut)
    }

    /// 脚本环境契约（spec §3.2.1）：
    /// - 外部脚本一律由 zsh 解释执行（无需可执行位），路径经 MENUMATE_SCRIPT 引用，禁止拼接进命令文本
    /// - $1..$n 与 MENUMATE_PATHS 传选中路径；MENUMATE_VARIANT 传子菜单值
    /// - 调用方经 extraEnv 注入 MENUMATE_TEMPLATES / MENUMATE_DATA
    /// - 契约 env（MENUMATE_VARIANT 等）覆盖 extraEnv，保证执行层语义不被调用方覆盖
    public static func runScript(_ spec: ScriptSpec, paths: [String], variant: String?,
                                 scriptBase: URL, cwd: URL?,
                                 extraEnv: [String: String] = [:]) -> ShellResult {
        // Contract env is applied AFTER extraEnv so it always wins.
        var env = extraEnv
        env["MENUMATE_PATHS"] = paths.joined(separator: "\n")
        env["MENUMATE_VARIANT"] = variant ?? ""
        let command: String
        if let resolved = spec.resolvedScriptPath(base: scriptBase) {
            env["MENUMATE_SCRIPT"] = resolved
            command = #"/bin/zsh "$MENUMATE_SCRIPT" "$@""#
        } else {
            command = spec.inlineSource ?? "true"
        }
        return run("/bin/zsh", ["-lc", command, "menumate"] + paths,
                   cwd: cwd, extraEnv: env, timeout: TimeInterval(spec.timeoutSeconds))
    }
}
