import XCTest
import Foundation
@testable import EasyContextCore

/// 直接解析 authored 的 Localizable.xcstrings 源文件，验证译文完整性。
/// 不依赖 String Catalog 的编译产物——SwiftPM 命令行不编译 .xcstrings，
/// 只有 Xcode 构建会。实际渲染由 App/扩展的 Xcode 构建 + 实机切语言验证。
/// 覆盖全部三份 catalog（Core / 宿主 / 扩展）：新增 key 忘翻译会在 swift test 被拦下。
final class LocalizationTests: XCTestCase {
    private let targetLangs = ["zh-Hans", "zh-Hant", "ja", "de", "fr", "es"] // en 是源语言，免翻
    // 品牌名 key：各语言与源相同，localizations 故意留空、回退源值。
    private let brandKeys: Set<String> = ["Markdown (.md)", "Shell (.sh)", "JSON (.json)"]

    /// repoRoot 相对路径 → catalog JSON。三份 catalog 都从源码树读（编译无关，CLI 下稳定）。
    private func loadCatalog(_ relativePath: String) throws -> [String: Any] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent()  // EasyContextCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // EasyContextCore/ (package root)
            .deletingLastPathComponent()  // repo root
        let catalog = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: catalog)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let catalogs = [
        "EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings",
        "EasyContext/Localizable.xcstrings",
        "EasyContext/InfoPlist.xcstrings",
        "EasyContextFinder/Localizable.xcstrings",
    ]

    func testCatalogSourceLanguageIsEnglish() throws {
        for path in catalogs {
            let json = try loadCatalog(path)
            XCTAssertEqual(json["sourceLanguage"] as? String, "en", "\(path) 源语言应为 en")
        }
    }

    func testRequiredKeysPresent() throws {
        let coreStrings = try XCTUnwrap(try loadCatalog(catalogs[0])["strings"] as? [String: Any])
        for key in ["Untitled", "Text (.txt)", "Markdown (.md)", "Shell (.sh)", "JSON (.json)"] {
            XCTAssertNotNil(coreStrings[key], "Core catalog 缺 key：\(key)")
        }
        let finderStrings = try XCTUnwrap(try loadCatalog(catalogs[3])["strings"] as? [String: Any])
        for key in ["Copy Path", "Copy Relative Path", "New File",
                    "Open with %@", "Run %@ in %@", "Command"] {
            XCTAssertNotNil(finderStrings[key], "扩展 catalog 缺 key：\(key)")
        }
        XCTAssertNil(finderStrings["Open Terminal with %@"], "终端与编辑器应共用简洁的 Open with %@ 文案")
    }

    func testEveryNonBrandKeyHasAllSixNonEnglishTranslations() throws {
        for path in catalogs {
            let strings = try XCTUnwrap(try loadCatalog(path)["strings"] as? [String: Any])
            for (key, entry) in strings where !brandKeys.contains(key) {
                let locs = ((entry as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
                for lang in targetLangs {
                    let value = ((locs[lang] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                    XCTAssertNotNil(value, "\(path) 的 key「\(key)」缺 \(lang) 译文")
                    XCTAssertFalse((value ?? "").isEmpty, "\(path) 的 key「\(key)」的 \(lang) 译文为空")
                }
            }
        }
    }

    func testDefaultFileNameKeepsExtension() {
        XCTAssertTrue(FileTemplate.markdown.defaultFileName.hasSuffix(".md"))
        XCTAssertTrue(FileTemplate.json.defaultFileName.hasSuffix(".json"))
    }
}
