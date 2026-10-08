import XCTest
@testable import CodexIsland

final class CurrentRequestTests: XCTestCase {
    func testBootstrapRequestBeforeStateTail() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let request: [String: Any] = ["type": "event_msg", "timestamp": "2026-10-07T10:00:00Z",
                                    "payload": ["type": "user_message", "message": "Latest real request"]]
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0A)
        let output = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "function_call_output", "output": String(repeating: "x", count: 700_000)]])
        data.append(output)
        data.append(0x0A)
        try data.write(to: url)
        XCTAssertEqual(try RolloutParser.latestUserRequest(at: url)?.text, "Latest real request")
        var tailer = IncrementalJSONLTailer()
        XCTAssertFalse(try tailer.readNewLines(at: url).compactMap(RolloutParser.parse).contains { TaskReducer.extractUserRequest(from: $0) != nil })
    }

    private func event(_ payload: [String: Any], type: String = "event_msg", time: Double = 100) throws -> RolloutEvent {
        let object: [String: Any] = ["type": type, "timestamp": Date(timeIntervalSince1970: time).ISO8601Format(), "payload": payload]
        return try XCTUnwrap(RolloutParser.parse(line: JSONSerialization.data(withJSONObject: object)))
    }

    func testLatestRequestSurvivesCompletionAndDoesNotChangeChatTitle() throws {
        var task = IslandFixtures.snapshot("active").tasks[0]
        let title = task.title
        var reducer = TaskReducer()
        reducer.reduce(task: &task, events: [try event(["type": "user_message", "message": "First request"]),
                                            try event(["type": "task_complete"], time: 101),
                                            try event(["type": "user_message", "message": "Refine the hover tray"], time: 102)])
        XCTAssertEqual(task.latestUserRequest, "Refine the hover tray")
        XCTAssertEqual(task.currentRequestTitle, "Refine the hover tray")
        XCTAssertEqual(task.title, title)
        reducer.reduce(task: &task, events: [try event(["type": "user_message", "message": "Stale request"], time: 99)])
        XCTAssertEqual(task.latestUserRequest, "Refine the hover tray")
        let restored = try JSONDecoder().decode(TaskSnapshot.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(restored.latestUserRequest, task.latestUserRequest)
    }

    func testStructuredUserContentAndAttachmentEnvelope() throws {
        let content = "# Files mentioned by the user:\nimage.png\n## My request:\nMake the tray cleaner."
        let e = try event(["type": "message", "role": "user", "content": [
            ["type": "input_text", "text": content], ["type": "input_image", "image_url": "ignored"]]], type: "response_item")
        XCTAssertEqual(TaskReducer.extractUserRequest(from: e), "Make the tray cleaner.")
        let context = try event(["type": "user_message", "message": "<environment_context>metadata</environment_context>"])
        XCTAssertNil(TaskReducer.extractUserRequest(from: context))
        let assistant = try event(["type": "message", "role": "assistant", "content": [["type": "text", "text": "Not a request"]]], type: "response_item")
        XCTAssertNil(TaskReducer.extractUserRequest(from: assistant))
        let output = try event(["type": "function_call_output", "output": "user_message pretend"], type: "response_item")
        XCTAssertNil(TaskReducer.extractUserRequest(from: output))
    }

    func testShimmerOnlyRunsForVisibleWorkingStates() {
        XCTAssertTrue(TrayShimmer.enabled(state: .thinking, visible: true, animations: true, reducedMotion: false))
        for state in [ActivityState.idle, .completed, .failed, .cancelled, .waitingForInput, .attentionRequired] {
            XCTAssertFalse(TrayShimmer.enabled(state: state, visible: true, animations: true, reducedMotion: false))
        }
        XCTAssertFalse(TrayShimmer.enabled(state: .thinking, visible: false, animations: true, reducedMotion: false))
        XCTAssertFalse(TrayShimmer.enabled(state: .thinking, visible: true, animations: false, reducedMotion: false))
        XCTAssertFalse(TrayShimmer.enabled(state: .thinking, visible: true, animations: true, reducedMotion: true))
        XCTAssertEqual(TrayShimmer.phase(at: 0.625), 0.25)
        XCTAssertEqual(TrayShimmer.phase(at: 3.125), 0.25)
        XCTAssertEqual(TrayShimmer.phase(at: .nan), 0)
    }

    func testEveryWorkingLabelUsesTheSameShimmerPolicyAndCompactAlias() {
        for state in ActivityState.allCases {
            XCTAssertEqual(TrayShimmer.state(for: state.label), state)
            XCTAssertEqual(TrayShimmer.state(for: IslandDesign.compactLabel(state)), state)
            XCTAssertEqual(TrayShimmer.enabled(state: state, visible: true, animations: true, reducedMotion: false),
                           state.isActive && !state.needsAttention)
            XCTAssertFalse(TrayShimmer.enabled(state: state, visible: false, animations: true, reducedMotion: false))
            XCTAssertFalse(TrayShimmer.enabled(state: state, visible: true, animations: false, reducedMotion: false))
            XCTAssertFalse(TrayShimmer.enabled(state: state, visible: true, animations: true, reducedMotion: true))
        }
        XCTAssertEqual(TrayShimmer.state(for: ""), .idle)
    }
}
