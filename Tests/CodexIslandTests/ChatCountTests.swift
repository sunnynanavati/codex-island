import XCTest
@testable import CodexIsland

final class ChatCountTests: XCTestCase {
    func testMultipleAgentsAreCountedAsOneIndependentChat() throws {
        var snapshot = IslandFixtures.snapshot("active")
        var root = try XCTUnwrap(snapshot.tasks.first)
        root.agentCount = 8
        var child = TaskSnapshot(id: "child", title: "Internal work", workspacePath: nil, rolloutPath: nil,
                             state: .thinking, updatedAt: root.updatedAt, startedAt: nil,
                             completedTurns: [], activityIntervals: [], pendingQuestion: nil,
                             quota: nil, isChildAgent: true, agentCount: 1, error: nil, rootChatID: root.id)
        snapshot.tasks = [root, child]
        XCTAssertEqual(snapshot.activeChatCount, 1)
        XCTAssertEqual(snapshot.activeChatSummary, "1 active chat")
        XCTAssertEqual(snapshot.activeAgentCount, 9)
        root.state = .completed
        snapshot.tasks = [root, child]
        XCTAssertEqual(snapshot.activeChatCount, 1)
        child.state = .completed
        snapshot.tasks = [root, child]
        XCTAssertEqual(snapshot.activeChatCount, 0)
    }

    func testUnknownChildrenDoNotInflateChatCount() throws {
        var snapshot = IslandFixtures.snapshot("multiple")
        XCTAssertEqual(snapshot.activeChatCount, 5)
        XCTAssertEqual(snapshot.activeChatSummary, "5 active chats")
        var child = try XCTUnwrap(snapshot.tasks.first)
        child.isChildAgent = true
        child.rootChatID = nil
        snapshot.tasks = [child]
        XCTAssertEqual(snapshot.activeChatCount, 0)
        child.rootChatID = child.id
        snapshot.tasks = [child]
        XCTAssertEqual(snapshot.activeChatCount, 0)
    }
}
