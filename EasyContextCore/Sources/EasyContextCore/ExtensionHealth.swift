import Foundation

/// Finder 扩展的健康判断（纯逻辑，供宿主的看门狗使用）。
///
/// 背景：安装后几十秒内，系统服务（siriknowledged、iconservicesagent、CoreServicesUIAgent
/// 等）会多次重建 App 的 LaunchServices 登记，每次扩展登记都换新 UUID。访达若恰在此时
/// 断开扩展，可能不再重新拉起，右键菜单随之消失。正常情况下 FinderSync 扩展在访达
/// 运行期间常驻（监控目录包含 "/"），因此「访达在、扩展已启用、扩展进程却不在」即异常。
public enum ExtensionHealth {
    /// `pluginkit -m -i <id>` 输出中是否有任一登记处于启用状态（行首 '+'）。
    /// '-' 为已登记但用户停用，空为未登记。同一 id 可能有多行（顺序不定），任一启用即视为启用。
    public static func isEnabled(pluginkitListing output: String) -> Bool {
        output.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        }
    }

    public struct Observation: Equatable, Sendable {
        public var finderRunning: Bool
        public var extensionEnabled: Bool
        public var extensionRunning: Bool

        public init(finderRunning: Bool, extensionEnabled: Bool, extensionRunning: Bool) {
            self.finderRunning = finderRunning
            self.extensionEnabled = extensionEnabled
            self.extensionRunning = extensionRunning
        }

        /// 访达在运行、扩展已启用，但扩展进程不在：访达丢失了扩展。
        /// 用户停用扩展或访达未运行（例如正在重启）都不算异常。
        public var extensionLost: Bool {
            finderRunning && extensionEnabled && !extensionRunning
        }
    }

    /// 修复决策：连续两次观察到异常才修复（跨过访达重启等瞬时状态）；两次修复至少间隔
    /// `minimumRepairInterval`；连续修复 `maximumConsecutiveRepairs` 次仍无效则停手，
    /// 避免无休止地停用 / 启用扩展。
    public struct RepairPolicy: Equatable, Sendable {
        public var minimumRepairInterval: TimeInterval = 60
        public var maximumConsecutiveRepairs = 3

        private(set) var consecutiveLost = 0
        private(set) var consecutiveRepairs = 0
        private(set) var lastRepair: Date?

        public init() {}

        public var gaveUp: Bool { consecutiveRepairs >= maximumConsecutiveRepairs }

        /// 已观察到一次异常、尚待复核：调用方应尽快再观察一次，而不是等完整的检查周期。
        public var awaitingConfirmation: Bool { consecutiveLost > 0 && !gaveUp }

        /// 记录一次观察，返回此刻是否应执行修复（返回 true 时已计入一次修复）。
        public mutating func shouldRepair(after observation: Observation, at now: Date) -> Bool {
            guard observation.extensionLost else {
                consecutiveLost = 0
                // 扩展确实在运行才说明修复奏效；访达未运行 / 扩展被停用时保持计数。
                if observation.finderRunning && observation.extensionEnabled && observation.extensionRunning {
                    consecutiveRepairs = 0
                }
                return false
            }
            consecutiveLost += 1
            guard consecutiveLost >= 2, !gaveUp else { return false }
            if let lastRepair, now.timeIntervalSince(lastRepair) < minimumRepairInterval { return false }
            lastRepair = now
            consecutiveRepairs += 1
            consecutiveLost = 0
            return true
        }
    }
}
