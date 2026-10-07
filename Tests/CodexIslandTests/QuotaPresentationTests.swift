import XCTest
@testable import CodexIsland

final class QuotaPresentationTests: XCTestCase {
    func testQuotaWarningBoundariesMatchRing() {
        for (remaining, severity) in [(0.0, QuotaSeverity.critical), (24.99, .critical),
                                      (25, .warning), (39.99, .warning), (40, .normal), (100, .normal)] {
            let quota = QuotaWindow(usedPercent: 100 - remaining, windowMinutes: 10080, resetAt: nil)
            XCTAssertEqual(QuotaSeverity(quota: quota), severity)
            XCTAssertEqual(CompactQuotaState(quota: quota).isCritical, severity == .critical)
        }
    }

    func testUnavailableQuotaNeverBecomesWarning() {
        XCTAssertEqual(QuotaSeverity(quota: nil), .unavailable)
        for value in [Double.nan, .infinity, -.infinity] {
            let quota = QuotaWindow(usedPercent: value, windowMinutes: 10080, resetAt: nil)
            XCTAssertEqual(QuotaSeverity(quota: quota), .unavailable)
            XCTAssertFalse(CompactQuotaState(quota: quota).isCritical)
        }
    }
}
