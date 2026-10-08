import XCTest
@testable import CodexIsland

final class TrayMetadataTests: XCTestCase {
    func testMinuteMinimumAndCompactAgeUnits() {
        let now = Date(timeIntervalSince1970: 200_000)
        for seconds in [-10.0, 0, 27, 59, 60, 119] {
            XCTAssertEqual(TrayAge(date: now.addingTimeInterval(-seconds), now: now).label, "1m ago")
        }
        XCTAssertEqual(TrayAge(date: now.addingTimeInterval(-120), now: now).label, "2m ago")
        XCTAssertEqual(TrayAge(date: now.addingTimeInterval(-3600), now: now).label, "1h ago")
        XCTAssertEqual(TrayAge(date: now.addingTimeInterval(-86400), now: now).label, "1d ago")
    }
    func testTickerPlaceValueIdentity() {
        XCTAssertEqual(TrayNumberTicker.digits(9), [9])
        XCTAssertEqual(TrayNumberTicker.digits(10), [0, 1])
        XCTAssertEqual(TrayNumberTicker.digits(101), [1, 0, 1])
        XCTAssertEqual(TrayNumberTicker.digits(-1), [0])
    }
    func testLocalUnreadSchemaDuplicatesChildrenAndUnknownData() throws {
        let a = UUID().uuidString, b = UUID().uuidString, child = UUID().uuidString
        let object: [String: Any] = ["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["account": ["local:host": [a, b, child], "local:other": [a], "remote:host": [UUID().uuidString]]]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(CodexUnreadState.count(data: data, excluding: [child]), 2)
        XCTAssertNil(CodexUnreadState.count(data: Data("{}".utf8), excluding: []))
        let multiple: [String: Any] = ["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["a": ["local:host": [a]], "b": ["local:host": [b]]]]]
        XCTAssertNil(CodexUnreadState.count(data: try JSONSerialization.data(withJSONObject: multiple), excluding: []))
    }
}
