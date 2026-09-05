import Foundation

/// Easy Context 发布版本只接受稳定的 `X.Y.Z` 三段数字。
public struct SemanticVersion: Codable, Comparable, CustomStringConvertible, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  !(part.count > 1 && part.first == "0"),
                  let value = Int(part) else { return nil }
            values.append(value)
        }

        major = values[0]
        minor = values[1]
        patch = values[2]
    }

    public init?(releaseTag: String) {
        guard releaseTag.first == "v" else { return nil }
        self.init(string: String(releaseTag.dropFirst()))
    }

    public var description: String { "\(major).\(minor).\(patch)" }
    public var releaseTag: String { "v\(description)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let parsed = SemanticVersion(string: value) else {
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Expected a stable X.Y.Z version")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// 通过 GitHub API 验证过、可安全展示给用户的稳定版本。
public struct EasyContextRelease: Codable, Equatable, Sendable {
    public let version: SemanticVersion
    public let tag: String
    public let pageURL: URL

    public init(version: SemanticVersion) {
        self.version = version
        tag = version.releaseTag
        pageURL = Self.trustedPageURL(for: version)
    }

    public var isTrusted: Bool {
        tag == version.releaseTag && pageURL == Self.trustedPageURL(for: version)
    }

    public static func trustedPageURL(for version: SemanticVersion) -> URL {
        // `SemanticVersion` 只有 ASCII 数字和点，构造出的 URL 无需接受 API 返回的 URL。
        URL(string: "https://github.com/yantaolu/easy-context/releases/tag/\(version.releaseTag)")!
    }
}

public enum UpdateCheckFailure: Error, Equatable, Sendable {
    case invalidCurrentVersion
    case invalidRelease
    case timedOut
    case network
    case httpStatus(Int)
    case rateLimited(until: Date)
}

public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(EasyContextRelease)
    case upToDate
    case failed(UpdateCheckFailure)
}

public enum UpdateCheckTrigger: Equatable, Sendable {
    case automatic
    case manual
}

public enum UpdateCheckSkipReason: Equatable, Sendable {
    case automaticChecksDisabled
    case checkedRecently
    case automaticBackoff
    case rateLimited(until: Date)
}

public enum UpdateCheckDisposition: Equatable, Sendable {
    case completed(UpdateCheckResult)
    case skipped(UpdateCheckSkipReason)
}

public struct UpdateHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

public protocol UpdateHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> UpdateHTTPResponse
}

/// 无持久 Cookie、无凭据、无磁盘 URL cache 的更新查询传输层。
public final class URLSessionUpdateTransport: UpdateHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let delegate: NoRedirectSessionDelegate

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = NoRedirectSessionDelegate()
        self.delegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> UpdateHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckFailure.network
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let key = pair.key as? String else { return }
            result[key.lowercased()] = String(describing: pair.value)
        }
        return UpdateHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

private final class NoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public protocol LatestReleaseFetching: Sendable {
    func fetchLatestRelease(now: Date) async -> Result<EasyContextRelease, UpdateCheckFailure>
}

/// GitHub `/releases/latest` 客户端。不会下载资产或执行安装。
public struct GitHubLatestReleaseClient: LatestReleaseFetching, Sendable {
    public static let endpoint = URL(string: "https://api.github.com/repos/yantaolu/easy-context/releases/latest")!

    private let transport: any UpdateHTTPTransport

    public init(transport: any UpdateHTTPTransport = URLSessionUpdateTransport()) {
        self.transport = transport
    }

    public func fetchLatestRelease(now: Date) async -> Result<EasyContextRelease, UpdateCheckFailure> {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EasyContext-UpdateChecker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let response: UpdateHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timedOut)
        } catch let failure as UpdateCheckFailure {
            return .failure(failure)
        } catch {
            return .failure(.network)
        }

        if response.statusCode == 403 || response.statusCode == 429 {
            return .failure(.rateLimited(until: retryDate(response: response, now: now)))
        }
        guard response.statusCode == 200 else {
            return .failure(.httpStatus(response.statusCode))
        }

        let payload: APIRelease
        do {
            payload = try JSONDecoder().decode(APIRelease.self, from: response.body)
        } catch {
            return .failure(.invalidRelease)
        }

        guard !payload.draft,
              !payload.prerelease,
              let version = SemanticVersion(releaseTag: payload.tagName),
              hasRequiredAssets(payload.assets, version: version) else {
            return .failure(.invalidRelease)
        }
        return .success(EasyContextRelease(version: version))
    }

    private func hasRequiredAssets(_ assets: [APIAsset], version: SemanticVersion) -> Bool {
        let prefix = "EasyContext-\(version.description)-macOS-"
        let required = [
            "\(prefix)arm64.pkg",
            "\(prefix)arm64.pkg.sha256",
            "\(prefix)x86_64.pkg",
            "\(prefix)x86_64.pkg.sha256",
        ]
        let validNames = Set(assets.compactMap { asset in
            asset.state == "uploaded" && asset.size > 0 ? asset.name : nil
        })
        return required.allSatisfy(validNames.contains)
    }

    private func retryDate(response: UpdateHTTPResponse, now: Date) -> Date {
        if let retryAfter = response.header("Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if let seconds = TimeInterval(retryAfter), seconds.isFinite, seconds >= 0 {
                return now.addingTimeInterval(seconds)
            }
            if let date = Self.httpDate(retryAfter), date > now {
                return date
            }
        }
        if let reset = response.header("X-RateLimit-Reset")?.trimmingCharacters(in: .whitespacesAndNewlines),
           let timestamp = TimeInterval(reset), timestamp.isFinite,
           timestamp > now.timeIntervalSince1970 {
            return Date(timeIntervalSince1970: timestamp)
        }
        return now.addingTimeInterval(60 * 60)
    }

    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss z", "EEEE',' dd-MMM-yy HH':'mm':'ss z", "EEE MMM d HH':'mm':'ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private struct APIRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [APIAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft, prerelease, assets
    }
}

private struct APIAsset: Decodable {
    let name: String
    let state: String
    let size: Int
}

/// 宿主负责用 UserDefaults 实现；Core 仅定义策略所需的最小状态。
@MainActor
public protocol UpdateCheckStorage: AnyObject {
    var automaticChecksEnabled: Bool { get set }
    var lastAttempt: Date? { get set }
    var lastSuccessfulCheck: Date? { get set }
    var automaticRetryAfter: Date? { get set }
    var serverRetryAfter: Date? { get set }
    var cachedRelease: EasyContextRelease? { get set }
}

/// 统一处理 24 小时限频、失败退避、服务端限流和同进程并发合并。
@MainActor
public final class UpdateCheckService {
    public static let automaticInterval: TimeInterval = 24 * 60 * 60
    public static let automaticFailureBackoff: TimeInterval = 60 * 60

    private let client: any LatestReleaseFetching
    private let storage: any UpdateCheckStorage
    private let now: @MainActor @Sendable () -> Date
    private var inFlight: Task<UpdateCheckResult, Never>?

    public init(client: any LatestReleaseFetching = GitHubLatestReleaseClient(),
                storage: any UpdateCheckStorage,
                now: @escaping @MainActor @Sendable () -> Date = { Date() }) {
        self.client = client
        self.storage = storage
        self.now = now
    }

    public func check(currentVersion: String,
                      trigger: UpdateCheckTrigger) async -> UpdateCheckDisposition {
        let currentDate = now()

        if trigger == .automatic && !storage.automaticChecksEnabled {
            return .skipped(.automaticChecksDisabled)
        }
        if let lastAttempt = storage.lastAttempt, currentDate < lastAttempt {
            // 系统时钟回拨后，旧的绝对时间不能继续长期压住检查。
            storage.lastAttempt = currentDate
            storage.lastSuccessfulCheck = nil
            storage.automaticRetryAfter = nil
            if storage.serverRetryAfter != nil {
                // 仍给 GitHub 一小时保护窗，避免时钟异常时立即冲击已知的服务端限流。
                storage.serverRetryAfter = currentDate.addingTimeInterval(Self.automaticFailureBackoff)
            }
        }
        // 已发出的请求永远复用，避免手动按钮与窗口打开同时制造第二个请求。
        if let inFlight {
            return .completed(await inFlight.value)
        }
        if let retry = storage.serverRetryAfter, retry > currentDate {
            return trigger == .manual
                ? .completed(.failed(.rateLimited(until: retry)))
                : .skipped(.rateLimited(until: retry))
        }
        if trigger == .automatic {
            if let last = storage.lastSuccessfulCheck {
                let elapsed = currentDate.timeIntervalSince(last)
                if elapsed >= 0 && elapsed < Self.automaticInterval {
                    return .skipped(.checkedRecently)
                }
            }
            if let retry = storage.automaticRetryAfter, retry > currentDate {
                return .skipped(.automaticBackoff)
            }
        }
        guard let installedVersion = SemanticVersion(string: currentVersion) else {
            return .completed(.failed(.invalidCurrentVersion))
        }

        let client = self.client
        storage.lastAttempt = currentDate
        let task = Task<UpdateCheckResult, Never> {
            switch await client.fetchLatestRelease(now: currentDate) {
            case .success(let release):
                return release.version > installedVersion ? .updateAvailable(release) : .upToDate
            case .failure(let failure):
                return .failed(failure)
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        apply(result, trigger: trigger, at: currentDate)
        return .completed(result)
    }

    private func apply(_ result: UpdateCheckResult, trigger: UpdateCheckTrigger, at date: Date) {
        switch result {
        case .updateAvailable(let release):
            storage.lastSuccessfulCheck = date
            storage.automaticRetryAfter = nil
            storage.serverRetryAfter = nil
            storage.cachedRelease = release
        case .upToDate:
            storage.lastSuccessfulCheck = date
            storage.automaticRetryAfter = nil
            storage.serverRetryAfter = nil
            storage.cachedRelease = nil
        case .failed(.rateLimited(let retry)):
            storage.serverRetryAfter = retry
        case .failed:
            if trigger == .automatic {
                storage.automaticRetryAfter = date.addingTimeInterval(Self.automaticFailureBackoff)
            }
        }
    }
}
