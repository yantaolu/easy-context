import XCTest
import Foundation
@testable import EasyContextCore

/// 直接解析 authored 的 Localizable.xcstrings 源文件，验证译文完整性。
/// 不依赖 String Catalog 的编译产物——SwiftPM 命令行不编译 .xcstrings，
/// 只有 Xcode 构建会。实际渲染由 App/扩展的 Xcode 构建 + 实机切语言验证。
final class LocalizationTests: XCTestCase {
    private let targetLangs = ["en", "zh-Hant", "ja", "de", "fr", "es"] // zh-Hans 是源语言，免翻
    // 品牌名 key：各语言与源相同，localizations 故意留空、回退源值。
    private let brandKeys: Set<String> = ["Markdown (.md)", "Shell (.sh)", "JSON (.json)"]

    private func loadCatalog() throws -> [String: Any] {
        // 从源码树直接读 authored 文件（编译无关，CLI 下稳定）。
        let thisFile = URL(fileURLWithPath: #filePath)
        let pkgRoot = thisFile
            .deletingLastPathComponent()  // EasyContextCoreTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // EasyContextCore/ (package root)
        let catalog = pkgRoot.appendingPathComponent("Sources/EasyContextCore/Localizable.xcstrings")
        let data = try Data(contentsOf: catalog)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testCatalogSourceLanguageIsSimplifiedChinese() throws {
        let json = try loadCatalog()
        XCTAssertEqual(json["sourceLanguage"] as? String, "zh-Hans")
    }

    func testRequiredCoreKeysPresent() throws {
        let strings = try XCTUnwrap(try loadCatalog()["strings"] as? [String: Any])
        for key in ["未命名", "文本 (.txt)", "Markdown (.md)", "Shell (.sh)", "JSON (.json)"] {
            XCTAssertNotNil(strings[key], "catalog 缺 key：\(key)")
        }
    }

    func testEveryNonBrandKeyHasAllSixTranslations() throws {
        let strings = try XCTUnwrap(try loadCatalog()["strings"] as? [String: Any])
        for (key, entry) in strings where !brandKeys.contains(key) {
            let locs = ((entry as? [String: Any])?["localizations"] as? [String: Any]) ?? [:]
            for lang in targetLangs {
                let value = ((locs[lang] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertNotNil(value, "key「\(key)」缺 \(lang) 译文")
                XCTAssertFalse((value ?? "").isEmpty, "key「\(key)」的 \(lang) 译文为空")
            }
        }
    }

    func testDefaultFileNameKeepsExtension() {
        XCTAssertTrue(FileTemplate.markdown.defaultFileName.hasSuffix(".md"))
        XCTAssertTrue(FileTemplate.json.defaultFileName.hasSuffix(".json"))
    }
}
