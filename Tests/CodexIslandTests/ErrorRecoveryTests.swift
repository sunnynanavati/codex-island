import XCTest
@testable import CodexIsland

final class ErrorRecoveryTests: XCTestCase {
    func testDatabaseErrorsOfferSafeRecoveryAndKeepDiagnosticDetail() throws {
        let missing = try XCTUnwrap(CodexDataError.databaseMissing.errorDescription)
        XCTAssertTrue(missing.contains("Open Codex"))
        XCTAssertTrue(missing.contains("refresh"))
        let unsupported = try XCTUnwrap(CodexDataError.noCompatibleTable.errorDescription)
        XCTAssertTrue(unsupported.contains("updates"))
        XCTAssertTrue(unsupported.contains("report"))
        XCTAssertTrue(unsupported.contains("do not delete"))
        let locked = try XCTUnwrap(CodexDataError.database("database is locked").errorDescription)
        XCTAssertTrue(locked.contains("Refresh to retry"))
        XCTAssertTrue(locked.contains("database is locked"))
    }
}
