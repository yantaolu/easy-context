import XCTest
@testable import EasyContextCore

final class FileTemplateTests: XCTestCase {
    func test_shell_hasShebangAndIsExecutable() {
        XCTAssertEqual(FileTemplate.shell.fileExtension, "sh")
        XCTAssertEqual(FileTemplate.shell.initialContent, "#!/bin/bash\n")
        XCTAssertTrue(FileTemplate.shell.isExecutable)
    }

    func test_json_hasEmptyObject() {
        XCTAssertEqual(FileTemplate.json.fileExtension, "json")
        XCTAssertEqual(FileTemplate.json.initialContent, "{}\n")
        XCTAssertFalse(FileTemplate.json.isExecutable)
    }

    func test_blank_hasNoExtensionNoContent() {
        XCTAssertEqual(FileTemplate.blank.fileExtension, "")
        XCTAssertEqual(FileTemplate.blank.initialContent, "")
    }
}
