import Foundation
import XCTest
@testable import EasyContextCore

/// 将带非 ASCII 字符的合成路径逐段送过启动协议。这里刻意不操作真实终端；外部工具均为
/// 临时目录中的 fake 可执行文件，以便把首个丢失 UTF-8 字节的阶段收敛到具体边界。
final class PathTransportTests: XCTestCase {
    private let path = "/Volumes/外置 磁盘/中文 'quote' \"$&;#%? 🍎/Cafe\u{301}"
    private let command = "codex --prompt '保留 $&;#%? 🍎'"
    private let hostileDirectory = "-中文-Cafe\u{301}-🍎-'\"-\\-$&;#%?-\n-\r-$()-`tick`-'); error \"EC_INJECTED\"; --"
    private let hostileCommand = "-claude '中文' \"NFD Cafe\u{301}\" 🍎 \\ $&;#%?\n\r$() `tick` '); error \"EC_INJECTED\"; --"

    /// 修复候选的阶段门：值作为 `osascript` 的两个 argv 传入，不再由
    /// AppleScript `system attribute` 从环境变量重新解码。此测试只返回 argv，
    /// 不 tell/open/control 任何真实终端。
    func test_candidate_osascriptRunArgv_preservesExactUTF8UnderLocaleVariants() throws {
        let candidate = #"""
        /usr/bin/osascript \
          -e 'on run argv' \
          -e 'return (item 1 of argv) & (character id 30) & (item 2 of argv)' \
          -e 'end run' \
          -- "$EC_DIR" "$EC_CMD"
        """#
        let variants: [(String, (inout [String: String]) -> Void)] = [
            ("inherited locale", { _ in }),
            ("locale removed", { env in
                env.removeValue(forKey: "LANG")
                env.removeValue(forKey: "LC_ALL")
                env.removeValue(forKey: "LC_CTYPE")
            }),
            ("C locale", { env in env["LC_ALL"] = "C" }),
        ]

        for (name, configure) in variants {
            var env = ProcessInfo.processInfo.environment
            configure(&env)
            env["EC_DIR"] = hostileDirectory
            env["EC_CMD"] = hostileCommand
            let result = try runShell(candidate, environment: env)
            XCTAssertEqual(result.status, 0, "\(name): \(result.stderr)")
            let payload = trimSingleTrailingNewline(result.output)
            let arguments = [UInt8](payload)
                .split(separator: UInt8(0x1E), omittingEmptySubsequences: false)
                .map { Data($0) }
            XCTAssertEqual(arguments.count, 2, "\(name): expected exactly two returned argv values")
            guard arguments.count == 2 else { continue }
            assertUTF8Data(arguments[0], equals: hostileDirectory,
                           stage: "/bin/sh → osascript argv[0] (\(name); \(localeDescription(env)))")
            assertUTF8Data(arguments[1], equals: hostileCommand,
                           stage: "/bin/sh → osascript argv[1] (\(name); \(localeDescription(env)))")
        }
    }

    func test_runURL_roundTripsUTF8IncludingNewline() throws {
        for path in [path, path + "\n下一行"] {
            var components = URLComponents()
            components.scheme = "easycontext"
            components.host = "run"
            components.queryItems = [
                URLQueryItem(name: "cmd", value: "Codex"),
                URLQueryItem(name: "dir", value: path),
                URLQueryItem(name: "term", value: "com.apple.Terminal"),
                URLQueryItem(name: "t", value: "test-token"),
            ]
            let url = try XCTUnwrap(components.url)
            let decoded = try XCTUnwrap(
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "dir" })?.value
            )
            assertUTF8(decoded, equals: path, stage: "URLComponents: \(url.absoluteString)")
        }
    }

    func test_getURLEventDirectObject_roundTripsUTF8() throws {
        let url = try makeRunURL(directory: path)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: url.absoluteString),
                       forKeyword: AEKeyword(keyDirectObject))
        let actual = try XCTUnwrap(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue)
        assertUTF8(actual, equals: url.absoluteString, stage: "GURL direct object")
        let decoded = try XCTUnwrap(URLComponents(url: try XCTUnwrap(URL(string: actual)),
                                                   resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "dir" })?.value)
        assertUTF8(decoded, equals: path, stage: "GURL → URLComponents")
    }

    func test_environmentToShell_preservesUTF8UnderLocaleVariants() throws {
        let variants: [(String, (inout [String: String]) -> Void)] = [
            ("inherited locale", { _ in }),
            ("locale removed", { env in
                env.removeValue(forKey: "LANG")
                env.removeValue(forKey: "LC_ALL")
                env.removeValue(forKey: "LC_CTYPE")
            }),
            ("C locale", { env in env["LC_ALL"] = "C" }),
        ]
        for (name, configure) in variants {
            var env = ProcessInfo.processInfo.environment
            configure(&env)
            env["EC_DIR"] = path + "\n下一行"
            let result = try runShell("printf '%s' \"$EC_DIR\"", environment: env)
            XCTAssertEqual(result.status, 0, "\(name): \(result.stderr)")
            assertUTF8Data(result.output, equals: env["EC_DIR"]!,
                           stage: "Process.environment → /bin/sh (\(name); \(localeDescription(env)))")
        }
    }

    func test_appleScriptTemplates_passExactlyTwoRawValuesAfterDoubleDash() throws {
        let templates: [(String, String)] = [
            ("Terminal", try template("com.apple.Terminal")),
            ("iTerm", try template("com.googlecode.iterm2")),
            ("cmux", try template(KnownApps.cmuxBundleId)),
            ("Ghostty", try template("com.mitchellh.ghostty")),
        ]
        for (name, template) in templates {
            let result = try runTemplate(template, fakeExecutable: "osascript",
                                         directory: hostileDirectory, command: hostileCommand)
            XCTAssertEqual(result.status, 0, "\(name): \(result.stderr)")
            XCTAssertEqual(result.arguments.count, 5, "\(name) should invoke osascript as -e SOURCE -- DIR CMD")
            guard result.arguments.count == 5 else { continue }
            XCTAssertEqual(result.arguments[0], Data("-e".utf8))
            let source = String(decoding: result.arguments[1], as: UTF8.self)
            XCTAssertTrue(source.contains("on run argv"), "\(name) should receive values through on run argv")
            XCTAssertFalse(source.contains("system attribute"), "\(name) must not locale-decode environment values")
            XCTAssertFalse(source.contains(hostileDirectory), "\(name) directory must not be interpolated into source")
            XCTAssertFalse(source.contains(hostileCommand), "\(name) command must not be interpolated into source")
            XCTAssertEqual(result.arguments[2], Data("--".utf8))
            assertUTF8Data(result.arguments[3], equals: hostileDirectory,
                           stage: "EC_DIR → fake osascript argv[0] (\(name))")
            assertUTF8Data(result.arguments[4], equals: hostileCommand,
                           stage: "EC_CMD → fake osascript argv[1] (\(name))")
        }
    }

    /// 用真实 osascript 执行与内置模板相同的 `on run argv` 包装，但 body
    /// 只返回待发给终端的文本；不 tell/open/control 任何应用。
    func test_appleScriptTemplate_realOsaScriptBuildsQuotedCommandWithoutSideEffects() throws {
        let template = TerminalLaunch.appleScriptTemplate("""
        return "cd " & quoted form of ecDir & " && " & ecCommand
        """)
        let variants: [(String, (inout [String: String]) -> Void)] = [
            ("inherited locale", { _ in }),
            ("locale removed", { env in
                env.removeValue(forKey: "LANG")
                env.removeValue(forKey: "LC_ALL")
                env.removeValue(forKey: "LC_CTYPE")
            }),
            ("C locale", { env in env["LC_ALL"] = "C" }),
        ]
        let expected = "cd " + shellQuoted(hostileDirectory) + " && " + hostileCommand
        for (name, configure) in variants {
            var env = ProcessInfo.processInfo.environment
            configure(&env)
            env["EC_DIR"] = hostileDirectory
            env["EC_CMD"] = hostileCommand
            let result = try runShell(template, environment: env)
            XCTAssertEqual(result.status, 0, "\(name): \(result.stderr)")
            assertUTF8Data(trimSingleTrailingNewline(result.output), equals: expected,
                           stage: "real osascript argv + quoted form (\(name); \(localeDescription(env)))")
        }
    }

    func test_openTemplates_passUnicodeDirectoryAsOneRawArgument() throws {
        let templates: [(String, String, String)] = [
            ("kitty", "net.kovidgoyal.kitty", "--directory"),
            ("WezTerm", "com.github.wez.wezterm", "--cwd"),
            ("Alacritty", "org.alacritty", "--working-directory"),
        ]
        for (name, bundleID, option) in templates {
            let result = try runTemplate(try template(bundleID), fakeExecutable: "open")
            XCTAssertEqual(result.status, 0, "\(name): \(result.stderr)")
            let optionData = Data(option.utf8)
            let indices = result.arguments.indices.filter { result.arguments[$0] == optionData }
            XCTAssertEqual(indices.count, 1, "\(name) should pass exactly one \(option)")
            let index = try XCTUnwrap(indices.first)
            XCTAssertLessThan(index + 1, result.arguments.count)
            XCTAssertEqual(result.arguments[index + 1], Data(path.utf8),
                           "\(name) cwd bytes differ; expected=\(hex(Data(path.utf8))) actual=\(hex(result.arguments[index + 1]))")
        }
    }

    func test_ottyCLI_receivesUnicodeCwdAsOneRawArgument() throws {
        let result = try runOttyTemplate()
        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(result.calls.count, 2)
        XCTAssertEqual(result.calls[0].map { String(decoding: $0, as: UTF8.self) }, ["window", "show", "current"])
        let tab = result.calls[1]
        XCTAssertEqual(tab.prefix(5).map { String(decoding: $0, as: UTF8.self) },
                       ["tab", "new", "--window", "current", "--cwd"])
        XCTAssertEqual(tab.count, 8)
        XCTAssertEqual(tab[5], Data(path.utf8),
                       "Otty --cwd bytes differ; expected=\(hex(Data(path.utf8))) actual=\(hex(tab[5]))")
    }

    /// 仅用于报告者本机的诊断：不 tell/open/control 任何终端，直接检查 Standard Additions
    /// `system attribute` 对固定合成路径的 UTF-8 读取与 cd 文本构造。默认跳过，避免 CI
    /// 依赖自动化权限或用户机器的 AppleScript 配置。
    func test_optIn_appleScriptSystemAttributePathDiagnostic() throws {
        guard ProcessInfo.processInfo.environment["EASYCONTEXT_RUN_APPLESCRIPT_PATH_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Set EASYCONTEXT_RUN_APPLESCRIPT_PATH_DIAGNOSTIC=1 to run the local AppleScript diagnostic.")
        }
        var env = ProcessInfo.processInfo.environment
        env["EC_DIR"] = path
        let attribute = try runProcess("/usr/bin/osascript", arguments: [
            "-e", "return system attribute \"EC_DIR\"",
        ], environment: env)
        XCTAssertEqual(attribute.status, 0,
                       "AppleScript system attribute failed (Standard Additions unavailable or blocked): \(attribute.stderr)")
        assertUTF8Data(trimSingleTrailingNewline(attribute.output), equals: path,
                       stage: "osascript system attribute; \(localeDescription(env))")

        let constructed = try runProcess("/usr/bin/osascript", arguments: [
            "-e", "set d to system attribute \"EC_DIR\"",
            "-e", "return \"cd \" & quoted form of d & \" && codex\"",
        ], environment: env)
        XCTAssertEqual(constructed.status, 0,
                       "AppleScript cd construction failed (Standard Additions unavailable or blocked): \(constructed.stderr)")
        let expected = "cd " + shellQuoted(path) + " && codex"
        assertUTF8Data(trimSingleTrailingNewline(constructed.output), equals: expected,
                       stage: "osascript quoted form; \(localeDescription(env))")
    }

    private func makeRunURL(directory: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "easycontext"
        components.host = "run"
        components.queryItems = [URLQueryItem(name: "dir", value: directory)]
        return try XCTUnwrap(components.url)
    }

    private func template(_ bundleID: String) throws -> String {
        try XCTUnwrap(TerminalLaunch.builtinTemplates[bundleID], "Missing template for \(bundleID)")
    }

    private func runTemplate(_ template: String, fakeExecutable: String,
                             directory: String? = nil, command commandValue: String? = nil) throws
        -> (status: Int32, environment: Data, arguments: [Data], stderr: String) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("EasyContext PathTransport \(UUID().uuidString)")
        let fake = root.appendingPathComponent(fakeExecutable)
        let environmentFile = root.appendingPathComponent("environment.bin")
        let argumentsDirectory = root.appendingPathComponent("arguments")
        let countFile = root.appendingPathComponent("argument-count")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let script = #"""
        #!/bin/sh
        mkdir -p "$FAKE_ARGUMENTS_DIRECTORY"
        printf '%s' "$EC_DIR" > "$FAKE_ENVIRONMENT_FILE"
        index=0
        for argument in "$@"; do
          printf '%s' "$argument" > "$FAKE_ARGUMENTS_DIRECTORY/$index"
          index=$((index + 1))
        done
        printf '%s' "$index" > "$FAKE_ARGUMENT_COUNT_FILE"
        """#
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = root.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["EC_DIR"] = directory ?? path
        env["EC_CMD"] = commandValue ?? command
        env["EC_SHELL"] = "/bin/sh"
        env["FAKE_ENVIRONMENT_FILE"] = environmentFile.path
        env["FAKE_ARGUMENTS_DIRECTORY"] = argumentsDirectory.path
        env["FAKE_ARGUMENT_COUNT_FILE"] = countFile.path
        var rendered = TerminalLaunch.render(template)
        if fakeExecutable == "osascript" {
            rendered = rendered.replacingOccurrences(of: "/usr/bin/osascript", with: shellQuoted(fake.path))
        }
        let result = try runShell(rendered, environment: env)
        let count = Int(try String(contentsOf: countFile, encoding: .utf8)) ?? 0
        let arguments = try (0..<count).map { try Data(contentsOf: argumentsDirectory.appendingPathComponent("\($0)")) }
        return (result.status, try Data(contentsOf: environmentFile), arguments, result.stderr)
    }

    private func runOttyTemplate() throws -> (status: Int32, calls: [[Data]], stderr: String) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("EasyContext Otty Unicode \(UUID().uuidString)")
        let cli = root.appendingPathComponent("otty-cli")
        let callsDirectory = root.appendingPathComponent("calls")
        let countFile = root.appendingPathComponent("call-count")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let script = #"""
        #!/bin/sh
        mkdir -p "$FAKE_OTTY_CALLS_DIRECTORY"
        call=$(cat "$FAKE_OTTY_CALL_COUNT_FILE" 2>/dev/null || printf 0)
        directory="$FAKE_OTTY_CALLS_DIRECTORY/$call"
        mkdir -p "$directory"
        index=0
        for argument in "$@"; do
          printf '%s' "$argument" > "$directory/$index"
          index=$((index + 1))
        done
        printf '%s' "$index" > "$directory/count"
        printf '%s' $((call + 1)) > "$FAKE_OTTY_CALL_COUNT_FILE"
        [ "$1" = window ] && exit 0
        [ "$1" = tab ] && exit 0
        exit 99
        """#
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        var env = ProcessInfo.processInfo.environment
        env["EC_DIR"] = path
        env["EC_CMD"] = command
        env["EC_OTTY_CLI"] = cli.path
        env["FAKE_OTTY_CALLS_DIRECTORY"] = callsDirectory.path
        env["FAKE_OTTY_CALL_COUNT_FILE"] = countFile.path
        let result = try runShell(TerminalLaunch.render(try template("io.appmakes.otty")), environment: env)
        let count = Int(try String(contentsOf: countFile, encoding: .utf8)) ?? 0
        let calls = try (0..<count).map { call -> [Data] in
            let directory = callsDirectory.appendingPathComponent("\(call)")
            let count = Int(try String(contentsOf: directory.appendingPathComponent("count"), encoding: .utf8)) ?? 0
            return try (0..<count).map { try Data(contentsOf: directory.appendingPathComponent("\($0)")) }
        }
        return (result.status, calls, result.stderr)
    }

    private func runShell(_ script: String, environment: [String: String]) throws
        -> (status: Int32, output: Data, stderr: String) {
        try runProcess("/bin/sh", arguments: ["-c", script], environment: environment)
    }

    private func runProcess(_ executable: String, arguments: [String], environment: [String: String]) throws
        -> (status: Int32, output: Data, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus,
                output.fileHandleForReading.readDataToEndOfFile(),
                String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func assertUTF8(_ actual: String, equals expected: String, stage: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        assertUTF8Data(Data(actual.utf8), equals: expected, stage: stage, file: file, line: line)
    }

    private func assertUTF8Data(_ actual: Data, equals expected: String, stage: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let expectedData = Data(expected.utf8)
        XCTAssertEqual(actual, expectedData,
                       "\(stage) UTF-8 differs; expected=\(hex(expectedData)) actual=\(hex(actual))",
                       file: file, line: line)
    }

    private func trimSingleTrailingNewline(_ data: Data) -> Data {
        data.last == 0x0A ? Data(data.dropLast()) : data
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func localeDescription(_ environment: [String: String]) -> String {
        ["LANG", "LC_ALL", "LC_CTYPE"].map { "\($0)=\(environment[$0] ?? "<unset>")" }.joined(separator: ", ")
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
