import XCTest
@testable import CodexIsland

final class DailyChatActivityTests: XCTestCase {
    private let first = "11111111-1111-4111-8111-111111111111"
    private let second = "22222222-2222-4222-8222-222222222222"
    private let child = "33333333-3333-4333-8333-333333333333"

    private func data(_ entries: [(String, String, Date)]) throws -> Data {
        var times: [String: Double] = [:]
        for (host, id, date) in entries {
            let key = String(decoding: try JSONSerialization.data(withJSONObject: [host, id]), as: UTF8.self)
            times[key] = date.timeIntervalSince1970 * 1000
        }
        return try JSONSerialization.data(withJSONObject: ["electron-persisted-atom-state": ["thread-user-activity-times-v1": times]])
    }

    func testCountsDistinctLocalChatsTodayExcludingChildrenAndOtherDays() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = try data([("local", first, now), ("local:account", first, now),
                                ("local", second, now.addingTimeInterval(-86400)),
                                ("local", child, now), ("remote", second, now)])
        XCTAssertEqual(CodexDailyChatActivity.count(data: payload, now: now, excluding: [child]), 1)
    }

    func testMidnightResetsWithoutFileChangesAndRejectsFutureTimestamps() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let now = start.addingTimeInterval(3600)
        let payload = try data([("local", first, start), ("local", second, now.addingTimeInterval(60))])
        XCTAssertEqual(CodexDailyChatActivity.count(data: payload, now: now, excluding: [], calendar: calendar), 1)
        XCTAssertEqual(CodexDailyChatActivity.count(data: payload, now: start.addingTimeInterval(86400), excluding: [], calendar: calendar), 0)
    }

    func testUnavailableSourceDoesNotBecomeMisleadingZero() {
        XCTAssertNil(CodexDailyChatActivity.count(data: Data("{}".utf8), now: Date(), excluding: []))
        var snapshot = IslandSnapshot.empty
        XCTAssertEqual(snapshot.dailyChatSummary, "— active chats today")
        snapshot.dailyChatCount = 1
        XCTAssertEqual(snapshot.dailyChatSummary, "1 active chat today")
        XCTAssertEqual(snapshot.activeChatCount, 0) // Live running count remains independent.
    }
}
