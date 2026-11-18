import AppKit
import os
import EasyContextCore

/// Finder 扩展看门狗：访达丢失扩展时，自动把它重新加载回来。
///
/// 安装或更新后，系统服务会在几十秒到几分钟内多次重建 App 的登记；访达若恰在此时断开
/// 扩展，可能不再重新拉起，右键菜单就此消失（只能重启访达或注销恢复）。宿主常驻后台，
/// 定期检查「访达在运行、扩展已启用、扩展进程却不在」，确认后把扩展停用再启用——
/// 访达会立即重新加载它，无需重启访达。判定与限流规则见 `ExtensionHealth.RepairPolicy`。
@MainActor
final class ExtensionWatchdog {
    static let shared = ExtensionWatchdog()

    /// 安装后的重建集中在前几分钟：此期间密集检查，之后放缓。发现异常后很快复核一次。
    private static let intensiveWindow: TimeInterval = 300
    private static let intensiveInterval: TimeInterval = 15
    private static let relaxedInterval: TimeInterval = 30
    private static let confirmationDelay: TimeInterval = 5

    private let log = Logger(subsystem: "com.luyantao.easycontext", category: "watchdog")
    private let startedAt = Date()
    private var policy = ExtensionHealth.RepairPolicy()
    private var task: Task<Void, Never>?
    private let extensionBundleId = (Bundle.main.bundleIdentifier ?? "com.luyantao.easycontext") + ".finder"
    private let extensionExecutable = Bundle.main.builtInPlugInsURL?
        .appendingPathComponent("EasyContextFinder.appex/Contents/MacOS/EasyContextFinder").path

    private init() {}

    func start() {
        guard task == nil, extensionExecutable != nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(self.startedAt)
                let interval = self.policy.awaitingConfirmation ? Self.confirmationDelay
                    : elapsed < Self.intensiveWindow ? Self.intensiveInterval : Self.relaxedInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self.check()
            }
        }
    }

    private func check() async {
        guard let executable = extensionExecutable else { return }
        let finderRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.finder" }
        let bundleId = extensionBundleId
        let (enabled, running) = await Task.detached(priority: .utility) {
            // 无法判断（pluginkit 失败 / 超时）时按「未启用」处理：宁可不修，也不误停用扩展。
            let listing = Self.run("/usr/bin/pluginkit", ["-m", "-i", bundleId])
            let enabled = listing.map { $0.status == 0 && ExtensionHealth.isEnabled(pluginkitListing: $0.output) } ?? false
            return (enabled, Self.isProcessRunning(executable: executable))
        }.value

        let observation = ExtensionHealth.Observation(finderRunning: finderRunning,
                                                      extensionEnabled: enabled, extensionRunning: running)
        let wasGivenUp = policy.gaveUp
        guard policy.shouldRepair(after: observation, at: Date()) else {
            if policy.gaveUp && !wasGivenUp {
                log.error("Finder extension is still missing after repeated reloads; giving up until next launch")
            }
            return
        }
        log.notice("Finder extension is enabled but not running; reloading it")
        await Task.detached(priority: .utility) {
            _ = Self.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", bundleId])
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = Self.run("/usr/bin/pluginkit", ["-e", "use", "-i", bundleId])
        }.value
    }

    /// 是否有进程的可执行文件正是 `executable`（逐个比对进程的可执行文件路径）。
    /// 不用 `pgrep -f`：它匹配整条命令行，任何参数里带这条路径的进程（如 `tail -f`、
    /// 监控脚本）都会被误判为扩展在运行。按路径比对也不会把 Debug 版等其它副本算进来。
    nonisolated private static func isProcessRunning(executable: String) -> Bool {
        let target = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return true } // 无法枚举时按「在运行」处理，避免误修复
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return true }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE
        for pid in pids.prefix(Int(count)) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            if String(cString: buffer) == target { return true }
        }
        return false
    }

    /// 运行命令行工具，最多等 5 秒。启动失败或超时返回 nil。
    nonisolated private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let killTimer = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: killTimer)
        // 先读完管道再等退出，避免输出超过管道缓冲时互相等待。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killTimer.cancel()
        if process.terminationReason == .uncaughtSignal { return nil }
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
