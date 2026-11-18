import XCTest
@testable import EasyContextCore

final class ExtensionHealthTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let lost = ExtensionHealth.Observation(finderRunning: true, extensionEnabled: true, extensionRunning: false)
    private let healthy = ExtensionHealth.Observation(finderRunning: true, extensionEnabled: true, extensionRunning: true)

    func test_enabledListing() {
        XCTAssertTrue(ExtensionHealth.isEnabled(pluginkitListing: "+    com.luyantao.easycontext.finder(1.1.3)"))
        XCTAssertTrue(ExtensionHealth.isEnabled(pluginkitListing: "-    x(1.0)\n+    x(1.1.3)\n"))
        XCTAssertFalse(ExtensionHealth.isEnabled(pluginkitListing: "-    com.luyantao.easycontext.finder(1.1.3)"))
        XCTAssertFalse(ExtensionHealth.isEnabled(pluginkitListing: ""))
    }

    func test_lostOnlyWhenFinderRunsAndExtensionEnabled() {
        XCTAssertTrue(lost.extensionLost)
        XCTAssertFalse(healthy.extensionLost)
        XCTAssertFalse(ExtensionHealth.Observation(finderRunning: false, extensionEnabled: true, extensionRunning: false).extensionLost)
        XCTAssertFalse(ExtensionHealth.Observation(finderRunning: true, extensionEnabled: false, extensionRunning: false).extensionLost)
    }

    func test_requiresTwoConsecutiveLostObservations() {
        var policy = ExtensionHealth.RepairPolicy()
        XCTAssertFalse(policy.awaitingConfirmation)
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0))
        XCTAssertTrue(policy.awaitingConfirmation, "first lost observation asks for a quick re-check")
        XCTAssertTrue(policy.shouldRepair(after: lost, at: t0 + 5))
        XCTAssertFalse(policy.awaitingConfirmation)
    }

    func test_healthyObservationResetsTheStreak() {
        var policy = ExtensionHealth.RepairPolicy()
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0))
        XCTAssertFalse(policy.shouldRepair(after: healthy, at: t0 + 15))
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0 + 30))
        XCTAssertTrue(policy.shouldRepair(after: lost, at: t0 + 45))
    }

    func test_rateLimitsRepairs() {
        var policy = ExtensionHealth.RepairPolicy()
        _ = policy.shouldRepair(after: lost, at: t0)
        XCTAssertTrue(policy.shouldRepair(after: lost, at: t0 + 15))
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0 + 30))
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0 + 45), "within 60s of the repair at t0+15")
        XCTAssertFalse(policy.shouldRepair(after: lost, at: t0 + 74), "still within 60s")
        XCTAssertTrue(policy.shouldRepair(after: lost, at: t0 + 76), "60s elapsed since the last repair")
    }

    func test_givesUpAfterRepeatedIneffectiveRepairs() {
        var policy = ExtensionHealth.RepairPolicy()
        var t = t0
        var repairs = 0
        for _ in 0..<40 {
            if policy.shouldRepair(after: lost, at: t) { repairs += 1 }
            t += 60
        }
        XCTAssertEqual(repairs, 3)
        XCTAssertTrue(policy.gaveUp)
    }

    func test_successfulRecoveryResetsRepairBudget() {
        var policy = ExtensionHealth.RepairPolicy()
        var t = t0
        for _ in 0..<2 { _ = policy.shouldRepair(after: lost, at: t); t += 60 }
        _ = policy.shouldRepair(after: healthy, at: t); t += 60
        var repairs = 0
        for _ in 0..<40 {
            if policy.shouldRepair(after: lost, at: t) { repairs += 1 }
            t += 60
        }
        XCTAssertEqual(repairs, 3)
    }

    func test_disabledOrFinderDownDoesNotResetBudget() {
        var policy = ExtensionHealth.RepairPolicy()
        var t = t0
        for _ in 0..<8 { _ = policy.shouldRepair(after: lost, at: t); t += 60 }
        XCTAssertTrue(policy.gaveUp)
        _ = policy.shouldRepair(after: ExtensionHealth.Observation(finderRunning: false, extensionEnabled: true, extensionRunning: false), at: t)
        XCTAssertTrue(policy.gaveUp)
    }
}
