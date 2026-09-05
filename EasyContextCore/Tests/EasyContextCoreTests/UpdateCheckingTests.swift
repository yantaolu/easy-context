import XCTest
import Foundation
@testable import EasyContextCore

final class UpdateCheckingTests: XCTestCase {
    func testSemanticVersionIsStrictAndNumeric() {
        XCTAssertEqual(SemanticVersion(string: "1.0.10"), SemanticVersion(string: "1.0.10"))
        XCTAssertGreaterThan(SemanticVersion(string: "1.0.10")!, SemanticVersion(string: "1.0.9")!)
        XCTAssertGreaterThan(SemanticVersion(string: "2.0.0")!, SemanticVersion(string: "1.99.99")!)
        XCTAssertEqual(SemanticVersion(releaseTag: "v1.2.3")?.description, "1.2.3")
        for invalid in ["v1.2.3", "1.2", "1.2.3.4", "1.02.3", "1.2.3-beta", " 1.2.3", "١.٢.٣"] {
            XCTAssertNil(SemanticVersion(string: invalid), "应拒绝 \(invalid)")
        }
        for invalidTag in ["1.2.3", "V1.2.3", "v1.2.3-beta", "v01.2.3"] {
            XCTAssertNil(SemanticVersion(releaseTag: invalidTag), "应拒绝 \(invalidTag)")
        }
    }

    func testCachedReleaseDecodeCannotBypassVersionAndURLValidation() throws {
        let decoder = JSONDecoder()
        let invalidVersion = Data(#"{"version":"-1.2.3","tag":"v-1.2.3","pageURL":"https://github.com/yantaolu/easy-context/releases/tag/v-1.2.3"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(EasyContextRelease.self, from: invalidVersion))

        let untrustedURL = Data(#"{"version":"1.2.3","tag":"v1.2.3","pageURL":"https://evil.example/v1.2.3"}"#.utf8)
        let decoded = try decoder.decode(EasyContextRelease.self, from: untrustedURL)
        XCTAssertFalse(decoded.isTrusted)
    }

    func testGitHubClientAcceptsOnlyCompleteStableRelease() async throws {
        let body = try releaseJSON(version: "1.2.3")
        let transport = FakeTransport([.response(.init(statusCode: 200, body: body))])
        let result = await GitHubLatestReleaseClient(transport: transport)
            .fetchLatestRelease(now: Date(timeIntervalSince1970: 1_000))

        let release = try XCTUnwrap(try result.get())
        XCTAssertEqual(release.version.description, "1.2.3")
        XCTAssertEqual(release.pageURL.absoluteString,
                       "https://github.com/yantaolu/easy-context/releases/tag/v1.2.3")
        XCTAssertTrue(release.isTrusted)
        let transportSnapshot = await transport.snapshot()
        XCTAssertEqual(transportSnapshot.count, 1)
        XCTAssertTrue(transportSnapshot.secureEndpoint)
    }

    func testGitHubClientRejectsDraftPrereleaseInvalidVersionAndMissingAssets() async throws {
        let fixtures = [
            try releaseJSON(version: "1.2.3", draft: true),
            try releaseJSON(version: "1.2.3", prerelease: true),
            try releaseJSON(tag: "v1.2.3-beta", version: "1.2.3"),
            try releaseJSON(version: "1.2.3", omitAsset: "EasyContext-1.2.3-macOS-x86_64.pkg.sha256"),
            Data("not-json".utf8),
        ]

        for body in fixtures {
            let client = GitHubLatestReleaseClient(
                transport: FakeTransport([.response(.init(statusCode: 200, body: body))]))
            let result = await client.fetchLatestRelease(now: .distantPast)
            XCTAssertEqual(result, .failure(.invalidRelease))
        }
    }

    func testGitHubClientRequiresUploadedNonemptyAssets() async throws {
        let empty = try releaseJSON(version: "1.2.3", emptyAsset: "EasyContext-1.2.3-macOS-arm64.pkg")
        let pending = try releaseJSON(version: "1.2.3", pendingAsset: "EasyContext-1.2.3-macOS-x86_64.pkg")
        for body in [empty, pending] {
            let client = GitHubLatestReleaseClient(
                transport: FakeTransport([.response(.init(statusCode: 200, body: body))]))
            let result = await client.fetchLatestRelease(now: .distantPast)
            XCTAssertEqual(result, .failure(.invalidRelease))
        }
    }

    func testGitHubClientMapsTimeoutAndHTTPFailures() async {
        let timeout = GitHubLatestReleaseClient(transport: FakeTransport([.timeout]))
        let timeoutResult = await timeout.fetchLatestRelease(now: .distantPast)
        XCTAssertEqual(timeoutResult, .failure(.timedOut))

        let server = GitHubLatestReleaseClient(
            transport: FakeTransport([.response(.init(statusCode: 503, body: Data()))]))
        let serverResult = await server.fetchLatestRelease(now: .distantPast)
        XCTAssertEqual(serverResult, .failure(.httpStatus(503)))
    }

    func testGitHubClientHonorsRetryAfterAndRateLimitReset() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let retryAfter = GitHubLatestReleaseClient(transport: FakeTransport([
            .response(.init(statusCode: 429, headers: ["Retry-After": "120"], body: Data())),
        ]))
        let retryAfterResult = await retryAfter.fetchLatestRelease(now: now)
        XCTAssertEqual(retryAfterResult,
                       .failure(.rateLimited(until: now.addingTimeInterval(120))))

        let reset = GitHubLatestReleaseClient(transport: FakeTransport([
            .response(.init(statusCode: 403,
                            headers: ["X-RateLimit-Reset": "10600"], body: Data())),
        ]))
        let resetResult = await reset.fetchLatestRelease(now: now)
        XCTAssertEqual(resetResult,
                       .failure(.rateLimited(until: Date(timeIntervalSince1970: 10_600))))

        let httpDate = GitHubLatestReleaseClient(transport: FakeTransport([
            .response(.init(statusCode: 429,
                            headers: ["Retry-After": "Thu, 01 Jan 1970 03:03:20 GMT"],
                            body: Data())),
        ]))
        let httpDateResult = await httpDate.fetchLatestRelease(now: now)
        XCTAssertEqual(httpDateResult,
                       .failure(.rateLimited(until: Date(timeIntervalSince1970: 11_000))))

        let duplicateCaseHeaders = UpdateHTTPResponse(
            statusCode: 429,
            headers: ["Retry-After": "60", "retry-after": "120"],
            body: Data())
        XCTAssertNotNil(duplicateCaseHeaders.header("retry-after"))
    }

    @MainActor
    func testServiceComparesVersionsNumericallyAndCachesOnlyNewerRelease() async {
        let storage = MemoryUpdateStorage()
        let clock = TestClock(Date(timeIntervalSince1970: 20_000))
        let fetcher = FakeFetcher([
            .success(release("1.0.10")),
            .success(release("1.0.10")),
            .success(release("1.0.10")),
        ])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        let updateResult = await service.check(currentVersion: "1.0.9", trigger: .manual)
        XCTAssertEqual(updateResult, .completed(.updateAvailable(release("1.0.10"))))
        XCTAssertEqual(storage.cachedRelease, release("1.0.10"))
        let equalResult = await service.check(currentVersion: "1.0.10", trigger: .manual)
        XCTAssertEqual(equalResult, .completed(.upToDate))
        XCTAssertNil(storage.cachedRelease)
        let newerResult = await service.check(currentVersion: "1.1.0", trigger: .manual)
        XCTAssertEqual(newerResult, .completed(.upToDate))
    }

    @MainActor
    func testAutomaticChecksRespectPreferenceDailyGateAndClockRollback() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let storage = MemoryUpdateStorage()
        let clock = TestClock(now)
        let fetcher = FakeFetcher([.success(release("2.0.0")), .success(release("2.0.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        storage.automaticChecksEnabled = false
        let disabledResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(disabledResult, .skipped(.automaticChecksDisabled))

        storage.automaticChecksEnabled = true
        storage.lastSuccessfulCheck = now.addingTimeInterval(-60)
        let recentResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(recentResult, .skipped(.checkedRecently))

        storage.lastSuccessfulCheck = now.addingTimeInterval(60 * 60) // 系统时钟回拨
        let rollbackResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(rollbackResult, .completed(.updateAvailable(release("2.0.0"))))
        let countAfterRollback = await fetcher.count()
        XCTAssertEqual(countAfterRollback, 1)

        clock.date = now.addingTimeInterval(UpdateCheckService.automaticInterval + 1)
        let nextDayResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(nextDayResult, .completed(.updateAvailable(release("2.0.0"))))
        let countAfterNextDay = await fetcher.count()
        XCTAssertEqual(countAfterNextDay, 2)
    }

    @MainActor
    func testAutomaticNetworkFailureBacksOffButManualRetryBypassesIt() async {
        let now = Date(timeIntervalSince1970: 40_000)
        let storage = MemoryUpdateStorage()
        let clock = TestClock(now)
        let fetcher = FakeFetcher([.failure(.network), .success(release("1.1.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        let failureResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(failureResult, .completed(.failed(.network)))
        XCTAssertEqual(storage.automaticRetryAfter,
                       now.addingTimeInterval(UpdateCheckService.automaticFailureBackoff))
        let backedOffResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(backedOffResult, .skipped(.automaticBackoff))
        let manualResult = await service.check(currentVersion: "1.0.0", trigger: .manual)
        XCTAssertEqual(manualResult, .completed(.updateAvailable(release("1.1.0"))))
        XCTAssertNil(storage.automaticRetryAfter)
        let requestCount = await fetcher.count()
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testClockRollbackClearsAutomaticFailureBackoff() async {
        let firstDate = Date(timeIntervalSince1970: 80_000)
        let storage = MemoryUpdateStorage()
        let clock = TestClock(firstDate)
        let fetcher = FakeFetcher([.failure(.network), .success(release("1.1.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        let failure = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(failure, .completed(.failed(.network)))
        clock.date = firstDate.addingTimeInterval(-24 * 60 * 60)
        let recovered = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(recovered, .completed(.updateAvailable(release("1.1.0"))))
        let requestCount = await fetcher.count()
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testClockRollbackRebasesServerLimitOnceWithoutExtendingForever() async {
        let now = Date(timeIntervalSince1970: 90_000)
        let storage = MemoryUpdateStorage()
        storage.lastAttempt = now.addingTimeInterval(24 * 60 * 60)
        storage.serverRetryAfter = now.addingTimeInterval(25 * 60 * 60)
        let clock = TestClock(now)
        let fetcher = FakeFetcher([.success(release("1.1.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        let protected = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(protected,
                       .skipped(.rateLimited(until: now.addingTimeInterval(60 * 60))))
        clock.date = now.addingTimeInterval(60 * 60 + 1)
        let recovered = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(recovered, .completed(.updateAvailable(release("1.1.0"))))
        let requestCount = await fetcher.count()
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testServerRateLimitBlocksManualAndAutomaticUntilRetryDate() async {
        let now = Date(timeIntervalSince1970: 50_000)
        let retry = now.addingTimeInterval(300)
        let storage = MemoryUpdateStorage()
        let clock = TestClock(now)
        let fetcher = FakeFetcher([.failure(.rateLimited(until: retry)), .success(release("1.1.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage, now: { clock.date })

        let rateResult = await service.check(currentVersion: "1.0.0", trigger: .manual)
        XCTAssertEqual(rateResult, .completed(.failed(.rateLimited(until: retry))))
        let manualBlockedResult = await service.check(currentVersion: "1.0.0", trigger: .manual)
        XCTAssertEqual(manualBlockedResult, .completed(.failed(.rateLimited(until: retry))))
        let autoBlockedResult = await service.check(currentVersion: "1.0.0", trigger: .automatic)
        XCTAssertEqual(autoBlockedResult, .skipped(.rateLimited(until: retry)))
        let blockedRequestCount = await fetcher.count()
        XCTAssertEqual(blockedRequestCount, 1)

        clock.date = retry.addingTimeInterval(1)
        let recoveredResult = await service.check(currentVersion: "1.0.0", trigger: .manual)
        XCTAssertEqual(recoveredResult, .completed(.updateAvailable(release("1.1.0"))))
        let recoveredRequestCount = await fetcher.count()
        XCTAssertEqual(recoveredRequestCount, 2)
    }

    @MainActor
    func testConcurrentChecksShareOneRequest() async {
        let storage = MemoryUpdateStorage()
        let fetcher = FakeFetcher([.success(release("1.1.0"))], delayNanoseconds: 50_000_000)
        let service = UpdateCheckService(client: fetcher, storage: storage)

        async let first = service.check(currentVersion: "1.0.0", trigger: .manual)
        async let second = service.check(currentVersion: "1.0.0", trigger: .manual)
        let results = await [first, second]

        XCTAssertEqual(results[0], .completed(.updateAvailable(release("1.1.0"))))
        XCTAssertEqual(results[1], results[0])
        let requestCount = await fetcher.count()
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testInvalidInstalledVersionNeverStartsNetworkRequest() async {
        let storage = MemoryUpdateStorage()
        let fetcher = FakeFetcher([.success(release("1.1.0"))])
        let service = UpdateCheckService(client: fetcher, storage: storage)
        let result = await service.check(currentVersion: "dev", trigger: .manual)
        XCTAssertEqual(result, .completed(.failed(.invalidCurrentVersion)))
        let requestCount = await fetcher.count()
        XCTAssertEqual(requestCount, 0)
    }

    private func release(_ version: String) -> EasyContextRelease {
        EasyContextRelease(version: SemanticVersion(string: version)!)
    }

    private func releaseJSON(tag: String? = nil,
                             version: String,
                             draft: Bool = false,
                             prerelease: Bool = false,
                             omitAsset: String? = nil,
                             emptyAsset: String? = nil,
                             pendingAsset: String? = nil) throws -> Data {
        let prefix = "EasyContext-\(version)-macOS-"
        let names = [
            "\(prefix)arm64.pkg",
            "\(prefix)arm64.pkg.sha256",
            "\(prefix)x86_64.pkg",
            "\(prefix)x86_64.pkg.sha256",
        ]
        let assets: [[String: Any]] = names.compactMap { name in
            guard name != omitAsset else { return nil }
            return [
                "name": name,
                "state": name == pendingAsset ? "new" : "uploaded",
                "size": name == emptyAsset ? 0 : 100,
            ]
        }
        return try JSONSerialization.data(withJSONObject: [
            "tag_name": tag ?? "v\(version)",
            "html_url": "https://evil.example/download",
            "draft": draft,
            "prerelease": prerelease,
            "assets": assets,
        ])
    }
}

private actor FakeTransport: UpdateHTTPTransport {
    enum Item: Sendable {
        case response(UpdateHTTPResponse)
        case timeout
    }

    private var items: [Item]
    private(set) var requestCount = 0
    private(set) var lastRequestWasSecureEndpoint = false

    init(_ items: [Item]) { self.items = items }

    func send(_ request: URLRequest) async throws -> UpdateHTTPResponse {
        requestCount += 1
        lastRequestWasSecureEndpoint = request.url == GitHubLatestReleaseClient.endpoint
            && request.httpMethod == "GET"
            && request.value(forHTTPHeaderField: "Authorization") == nil
        guard !items.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        switch items.removeFirst() {
        case .response(let response): return response
        case .timeout: throw URLError(.timedOut)
        }
    }

    func snapshot() -> (count: Int, secureEndpoint: Bool) {
        (requestCount, lastRequestWasSecureEndpoint)
    }
}

private actor FakeFetcher: LatestReleaseFetching {
    private var results: [Result<EasyContextRelease, UpdateCheckFailure>]
    private let delayNanoseconds: UInt64
    private(set) var requestCount = 0

    init(_ results: [Result<EasyContextRelease, UpdateCheckFailure>],
         delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchLatestRelease(now: Date) async -> Result<EasyContextRelease, UpdateCheckFailure> {
        requestCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !results.isEmpty else { return .failure(.network) }
        return results.removeFirst()
    }

    func count() -> Int { requestCount }
}

@MainActor
private final class MemoryUpdateStorage: UpdateCheckStorage {
    var automaticChecksEnabled = true
    var lastAttempt: Date?
    var lastSuccessfulCheck: Date?
    var automaticRetryAfter: Date?
    var serverRetryAfter: Date?
    var cachedRelease: EasyContextRelease?
}

@MainActor
private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}
