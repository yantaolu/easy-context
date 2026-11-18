import XCTest
@testable import EasyContextCore

final class ExternalVolumesTests: XCTestCase {
    private func traits(isInternal: Bool = false, local: Bool = true,
                        browsable: Bool = true, root: Bool = false) -> ExternalVolumes.Traits {
        .init(isInternal: isInternal, isLocal: local, isBrowsable: browsable, isRootFileSystem: root)
    }

    func test_fixedExternalDrivesCount() {
        // 雷雳 / USB 固定盘：volumeIsRemovable 为 false，但仍受「可移除宗卷」授权控制。
        XCTAssertTrue(ExternalVolumes.isExternal(traits()))
    }

    func test_excludesInternalNetworkHiddenAndBootVolumes() {
        XCTAssertFalse(ExternalVolumes.isExternal(traits(isInternal: true)))
        XCTAssertFalse(ExternalVolumes.isExternal(traits(local: false)))
        XCTAssertFalse(ExternalVolumes.isExternal(traits(browsable: false)))
        XCTAssertFalse(ExternalVolumes.isExternal(traits(isInternal: true, root: true)))
    }

    func test_selectKeepsOrderAndSkipsUnknownVolumes() {
        let root = URL(fileURLWithPath: "/")
        let medias = URL(fileURLWithPath: "/Volumes/Medias")
        let nas = URL(fileURLWithPath: "/Volumes/NAS")
        let gone = URL(fileURLWithPath: "/Volumes/Gone")
        let docs = URL(fileURLWithPath: "/Volumes/Documents")
        let table: [URL: ExternalVolumes.Traits] = [
            root: traits(isInternal: true, root: true),
            medias: traits(),
            nas: traits(local: false),
            docs: traits(),
        ]
        XCTAssertEqual(ExternalVolumes.select([root, medias, nas, gone, docs]) { table[$0] },
                       [medias, docs])
    }
}

final class FolderOpenFailureTests: XCTestCase {
    private let token = "TOKEN-123"

    func test_roundTripsMultipleDirectoriesWithSpacesAndUnicode() throws {
        let failure = FolderOpenFailure(
            appBundleId: "com.googlecode.iterm2",
            directories: ["/Volumes/Medias", "/Volumes/外置 盘/项目 & 资料?#"],
            errorDomain: "NSOSStatusErrorDomain", errorCode: -54)
        let url = try XCTUnwrap(failure.url(scheme: "easycontext", token: token))
        XCTAssertEqual(FolderOpenFailure(url: url, scheme: "easycontext", expectedToken: token), failure)
    }

    func test_rejectsWrongTokenSchemeHostOrMissingFields() throws {
        let failure = FolderOpenFailure(appBundleId: "com.apple.Terminal", directories: ["/Volumes/Medias"],
                                        errorDomain: "d", errorCode: 1)
        let url = try XCTUnwrap(failure.url(scheme: "easycontext", token: token))
        XCTAssertNil(FolderOpenFailure(url: url, scheme: "easycontext", expectedToken: "other"))
        XCTAssertNil(FolderOpenFailure(url: url, scheme: "easycontext", expectedToken: ""))
        XCTAssertNil(FolderOpenFailure(url: url, scheme: "easycontext-debug", expectedToken: token))
        XCTAssertNil(FolderOpenFailure(url: URL(string: "easycontext://run?app=a&dir=/x&t=\(token)")!,
                                       scheme: "easycontext", expectedToken: token))
        XCTAssertNil(FolderOpenFailure(url: URL(string: "easycontext://open-error?dir=/x&t=\(token)")!,
                                       scheme: "easycontext", expectedToken: token))
        XCTAssertNil(FolderOpenFailure(url: URL(string: "easycontext://open-error?app=a&t=\(token)")!,
                                       scheme: "easycontext", expectedToken: token))
    }

    func test_missingErrorFieldsDefault() throws {
        let url = try XCTUnwrap(URL(string: "easycontext://open-error?app=a&dir=/x&t=\(token)"))
        let parsed = try XCTUnwrap(FolderOpenFailure(url: url, scheme: "easycontext", expectedToken: token))
        XCTAssertEqual(parsed.errorDomain, "")
        XCTAssertEqual(parsed.errorCode, 0)
    }
}

final class FolderAccessProbeTests: XCTestCase {
    func test_classifiesPermissionErrorsAsDenied() {
        XCTAssertEqual(FolderAccessProbe.classify(nil), .granted)
        XCTAssertEqual(FolderAccessProbe.classify(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)), .denied)
        XCTAssertEqual(FolderAccessProbe.classify(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))), .denied)
        XCTAssertEqual(FolderAccessProbe.classify(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))])),
            .denied)
    }

    func test_otherErrorsAreFailures() {
        XCTAssertEqual(FolderAccessProbe.classify(
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)), .failed)
        XCTAssertEqual(FolderAccessProbe.classify(
            NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))), .failed)
    }

    func test_probeReadsAnAccessibleDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(FolderAccessProbe.probe(dir.path), .granted)
        XCTAssertEqual(FolderAccessProbe.probe(dir.appendingPathComponent("missing").path), .failed)
    }
}
