import XCTest
import SQLite3
@testable import CodexIsland

final class LiveQuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func window(_ used: Double, _ minutes: Int) -> [String: Any] {
        ["usedPercent": used, "windowDurationMins": minutes, "resetsAt": now.addingTimeInterval(3600).timeIntervalSince1970]
    }
    func testCoreBucketOverridesOtherModelsAndLegacy() {
        let result: [String: Any] = ["rateLimitsByLimitId": ["codex": ["primary": window(0, 10080)], "other": ["primary": window(25, 10080)]],
                                    "rateLimits": ["primary": window(25, 10080)]]
        XCTAssertEqual(AccountQuotaParser.parse(result, now: now)?.remainingPercent, 100)
    }
    func testLongestWindowAndFractionalPercentage() {
        let result: [String: Any] = ["rateLimits": ["primary": window(60, 300), "secondary": window(0.5, 10080)]]
        XCTAssertEqual(AccountQuotaParser.parse(result, now: now)?.remainingPercent, 99.5)
    }
    func testMissingCoreDoesNotUseUnrelatedBucket() {
        XCTAssertNil(AccountQuotaParser.parse(["rateLimitsByLimitId": ["other": ["primary": window(20, 10080)]]], now: now))
        XCTAssertNil(AccountQuotaParser.parse(["rateLimits": ["limitId": "other", "primary": window(20, 10080)]], now: now))
    }
    func testMalformedAndExpiredReportsAreUnavailable() {
        XCTAssertNil(AccountQuotaParser.parse(["rateLimits": ["primary": window(-1, 10080)]], now: now))
        XCTAssertNil(AccountQuotaParser.parse(["rateLimits": ["primary": window(101, 10080)]], now: now))
        XCTAssertNil(AccountQuotaParser.parse(["rateLimits": ["primary": window(20, 0)]], now: now))
        XCTAssertNil(AccountQuotaParser.parse(["rateLimits": ["primary": window(20, 10080)]], now: now.addingTimeInterval(3601)))
    }
    func testFiveMinuteBudgetAndTenMinuteExpiry() {
        var cache = QuotaCache()
        XCTAssertTrue(cache.beginCheck(now: now))
        for second in 1..<300 { XCTAssertFalse(cache.beginCheck(now: now.addingTimeInterval(Double(second)))) }
        XCTAssertTrue(cache.beginCheck(now: now.addingTimeInterval(300)))
        cache.value = QuotaWindow(usedPercent: 0, windowMinutes: 10080, resetAt: now.addingTimeInterval(3600), observedAt: now)
        XCTAssertNotNil(cache.current(now: now.addingTimeInterval(599)))
        XCTAssertNil(cache.current(now: now.addingTimeInterval(600)))
    }
    func testResetInvalidatesCachedValueImmediately() {
        var cache = QuotaCache()
        cache.value = QuotaWindow(usedPercent: 25, windowMinutes: 10080, resetAt: now.addingTimeInterval(5), observedAt: now)
        XCTAssertNil(cache.current(now: now.addingTimeInterval(5)))
    }
    func testEmptyCompatibleDatabaseIsNotSchemaFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE threads (id TEXT, title TEXT, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        let snapshot = try await CodexDataStore(codexRoot: directory).loadSnapshot(now: now)
        XCTAssertTrue(snapshot.tasks.isEmpty)
        XCTAssertNil(snapshot.errorMessage)
    }
}
