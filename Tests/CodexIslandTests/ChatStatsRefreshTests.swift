import XCTest
import SQLite3
@testable import CodexIsland

final class ChatStatsRefreshTests: XCTestCase {
    func testUnreadReadChangesRefreshWithoutChangingDailyCountAndResetAtMidnight() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "CREATE TABLE threads (id TEXT, title TEXT, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(3600)
        let a = UUID().uuidString, b = UUID().uuidString
        let identity = String(decoding: try JSONSerialization.data(withJSONObject: ["local", a]), as: UTF8.self)
        let url = directory.appendingPathComponent(".codex-global-state.json")
        func write(unread: [String], stamp: Date) throws {
            let data = try JSONSerialization.data(withJSONObject: [
                "electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["account": ["local:host": unread]]],
                "electron-persisted-atom-state": ["thread-user-activity-times-v1": [identity: now.timeIntervalSince1970 * 1000]]
            ])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        }
        let store = CodexDataStore(codexRoot: directory)
        try write(unread: [a, b], stamp: now)
        let first = try await store.loadSnapshot(now: now)
        XCTAssertEqual(first.unreadCount, 2)
        XCTAssertEqual(first.dailyChatCount, 1)
        XCTAssertEqual(first.activeChatCount, 0)
        try write(unread: [b], stamp: now.addingTimeInterval(1))
        let read = try await store.loadSnapshot(now: now.addingTimeInterval(1))
        XCTAssertEqual(read.unreadCount, 1)
        XCTAssertEqual(read.dailyChatCount, first.dailyChatCount)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let reset = try await store.loadSnapshot(now: tomorrow)
        XCTAssertEqual(reset.dailyChatCount, 0)
        XCTAssertEqual(reset.unreadCount, 1) // Unread is account state, not a daily count.
        try FileManager.default.removeItem(at: url)
        let unavailable = try await store.loadSnapshot(now: tomorrow)
        XCTAssertNil(unavailable.unreadCount)
        XCTAssertNil(unavailable.dailyChatCount)
    }
}
