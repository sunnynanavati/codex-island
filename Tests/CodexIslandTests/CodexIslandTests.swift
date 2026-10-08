import AppKit
import SQLite3
import XCTest
import CoreText
import SwiftUI
@testable import CodexIsland

final class CodexIslandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        type: String = "event",
        text: String,
        payload: [String: JSONValue] = [:],
        timestamp: Date? = nil
    ) -> RolloutEvent {
        RolloutEvent(timestamp: timestamp ?? now, type: type, text: text.lowercased(), payload: payload)
    }

    private func task(
        id: String = "one",
        state: ActivityState = .idle,
        updated: Date? = nil,
        child: Bool = false
    ) -> TaskSnapshot {
        TaskSnapshot(
            id: id, title: "Test task", workspacePath: "/tmp/Test", rolloutPath: nil,
            state: state, updatedAt: updated ?? now, startedAt: nil,
            completedTurns: [], activityIntervals: [], pendingQuestion: nil, quota: nil,
            isChildAgent: child, agentCount: 1, error: nil
        )
    }

    func testActivityGrouping() {
        let tasks = [
            task(id: "active", state: .editing),
            task(id: "attention", state: .waitingForInput),
            task(id: "done", state: .completed),
            task(id: "child", state: .completed, child: true)
        ]
        let snapshot = IslandSnapshot(
            tasks: tasks, primaryTaskID: "active", dailyStats: .init(completedTurns: 0, activeDuration: 0),
            quota: nil, refreshedAt: now, errorMessage: nil
        )
        XCTAssertEqual(snapshot.activeTasks.map(\.id), ["active", "attention"])
        XCTAssertEqual(snapshot.recentTasks.map(\.id), ["done"])
        XCTAssertEqual(snapshot.attentionCount, 1)
        XCTAssertEqual(snapshot.activeAgentCount, 2)
    }

    func testPrimaryTaskStability() {
        var selector = PrimaryTaskSelector(minimumHold: 8)
        let first = task(id: "first", state: .editing, updated: now)
        let later = task(id: "later", state: .running, updated: now.addingTimeInterval(2))
        XCTAssertEqual(selector.select(from: [first], now: now), "first")
        XCTAssertEqual(selector.select(from: [first, later], now: now.addingTimeInterval(3)), "first")
        XCTAssertEqual(selector.select(from: [first, later], now: now.addingTimeInterval(9)), "later")
    }

    func testCompletionIsBrieflyAcknowledged() {
        var selector = PrimaryTaskSelector()
        let completed = task(id: "done", state: .completed, updated: now)
        XCTAssertEqual(selector.select(from: [completed], now: now.addingTimeInterval(2)), "done")
        XCTAssertNil(selector.select(from: [completed], now: now.addingTimeInterval(5)))
    }

    func testRolloutEventParsing() throws {
        let line = Data(#"{"timestamp":"2027-01-15T08:00:00Z","type":"tool_call","payload":{"name":"apply_patch"}}"#.utf8)
        let parsed = try XCTUnwrap(RolloutParser.parse(line: line))
        XCTAssertEqual(parsed.type, "tool_call")
        XCTAssertTrue(parsed.text.contains("apply_patch"))
        XCTAssertEqual(parsed.timestamp, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testFractionalRolloutTimestampParsing() throws {
        let line = Data(#"{"timestamp":"2027-01-15T08:00:00.125Z","type":"event_msg"}"#.utf8)
        let parsed = try XCTUnwrap(RolloutParser.parse(line: line))
        XCTAssertEqual(parsed.timestamp.timeIntervalSince1970, 1_800_000_000.125, accuracy: 0.001)
    }

    func testActivityClassification() {
        XCTAssertEqual(ActivityClassifier.classify(event(text: "apply_patch updated source")), .editing)
        XCTAssertEqual(ActivityClassifier.classify(event(text: "exec_command swift test")), .running)
        XCTAssertEqual(ActivityClassifier.classify(event(text: "request_user_input questions")), .waitingForInput)
        XCTAssertEqual(ActivityClassifier.classify(event(text: "assistant_message final_answer")), .writing)
    }

    func testStructuredRolloutClassificationIgnoresQuotedTaskText() {
        let quoted = event(
            type: "response_item", text: "user asked why the build failed and said done",
            payload: ["payload": .object(["type": .string("message"), "role": .string("user")])]
        )
        XCTAssertEqual(ActivityClassifier.classify(quoted), .idle)
        XCTAssertEqual(ActivityClassifier.classify(event(
            type: "event_msg", text: "",
            payload: ["payload": .object(["type": .string("task_complete")])]
        )), .completed)
        XCTAssertEqual(ActivityClassifier.classify(event(
            type: "event_msg", text: "",
            payload: ["payload": .object(["type": .string("turn_aborted")])]
        )), .cancelled)
        XCTAssertEqual(ActivityClassifier.classify(event(
            type: "response_item", text: "",
            payload: ["payload": .object([
                "type": .string("function_call"), "name": .string("request_user_input")
            ])]
        )), .waitingForInput)
    }

    func testCurrentCodexToolLifecycleReturnsToThinking() {
        func structured(_ type: String, name: String? = nil) -> RolloutEvent {
            var fields: [String: JSONValue] = ["type": .string(type)]
            if let name { fields["name"] = .string(name) }
            return event(type: "response_item", text: "", payload: ["payload": .object(fields)])
        }
        let call = structured("custom_tool_call", name: "exec")
        let output = structured("custom_tool_call_output")
        XCTAssertEqual(ActivityClassifier.classify(call), .running)
        XCTAssertEqual(ActivityClassifier.classify(output), .thinking)
        XCTAssertEqual(ActivityClassifier.classify(structured("function_call_output")), .thinking)

        var value = task(state: .thinking)
        var reducer = TaskReducer()
        reducer.reduce(task: &value, events: [call])
        XCTAssertEqual(value.state, .running)
        reducer.reduce(task: &value, events: [output])
        XCTAssertEqual(value.state, .thinking)
    }

    private func syntheticThinkingSnapshot(age: TimeInterval) async throws -> IslandSnapshot {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rollout = directory.appendingPathComponent("thread.jsonl")
        let oldTimestamp = now.addingTimeInterval(-age)
        let stamp = ISO8601DateFormatter().string(from: oldTimestamp)
        try Data("{\"timestamp\":\"\(stamp)\",\"type\":\"response_item\",\"payload\":{\"type\":\"reasoning\"}}\n".utf8)
            .write(to: rollout)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database,
            "CREATE TABLE threads (id TEXT, title TEXT, rollout_path TEXT, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        let insert = "INSERT INTO threads VALUES ('thread', 'Synthetic task', '\(rollout.path)', \(Int(oldTimestamp.timeIntervalSince1970)))"
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)
        return try await CodexDataStore(codexRoot: directory).loadSnapshot(now: now)
    }

    func testRecentQuietThinkingStepRemainsActive() async throws {
        let snapshot = try await syntheticThinkingSnapshot(age: 10 * 60)
        XCTAssertEqual(snapshot.primaryTask?.state, .thinking)
    }

    func testAbandonedThinkingStepBecomesIdle() async throws {
        let snapshot = try await syntheticThinkingSnapshot(age: 2 * 60 * 60)
        XCTAssertNil(snapshot.primaryTask)
        XCTAssertEqual(snapshot.tasks.first?.state, .idle)
    }

    func testLateCommandEventCannotReactivateCompletedTurn() {
        let started = event(type: "event_msg", text: "", payload: ["payload": .object([
            "type": .string("task_started")
        ])])
        let completed = event(type: "event_msg", text: "", payload: ["payload": .object([
            "type": .string("task_complete")
        ])], timestamp: now.addingTimeInterval(1))
        let lateCommand = event(type: "event_msg", text: "", payload: ["payload": .object([
            "type": .string("item_completed"),
            "item": .object(["type": .string("CommandExecution")])
        ])], timestamp: now.addingTimeInterval(3600))
        var value = task()
        var reducer = TaskReducer()
        reducer.reduce(task: &value, events: [started, completed, lateCommand])
        XCTAssertEqual(value.state, .completed)
        XCTAssertEqual(value.completedTurns.count, 1)
        XCTAssertEqual(reducer.lastActivityAt, completed.timestamp)
        reducer.reduce(task: &value, events: [started, lateCommand])
        XCTAssertEqual(value.state, .thinking)
    }

    func testSnapshotIgnoresLateCommandAndSettingsAfterCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rollout = directory.appendingPathComponent("thread.jsonl")
        func line(_ time: Date, _ type: String, item: String? = nil) -> String {
            let stamp = ISO8601DateFormatter().string(from: time)
            let itemField = item.map { ",\"item\":{\"type\":\"\($0)\"}" } ?? ""
            return "{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"\(itemField)}}\n"
        }
        let lines = line(now.addingTimeInterval(-7200), "task_started")
            + line(now.addingTimeInterval(-7140), "task_complete")
            + line(now.addingTimeInterval(-120), "item_completed", item: "CommandExecution")
            + line(now.addingTimeInterval(-60), "thread_settings_applied")
        try Data(lines.utf8).write(to: rollout)
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database,
            "CREATE TABLE threads (id TEXT, title TEXT, rollout_path TEXT, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        let insert = "INSERT INTO threads VALUES ('thread', 'Synthetic task', '\(rollout.path)', \(Int(now.addingTimeInterval(-60).timeIntervalSince1970)))"
        XCTAssertEqual(sqlite3_exec(database, insert, nil, nil, nil), SQLITE_OK)
        let snapshot = try await CodexDataStore(codexRoot: directory).loadSnapshot(now: now)
        XCTAssertEqual(snapshot.tasks.first?.state, .completed)
        XCTAssertTrue(snapshot.activeTasks.isEmpty)
        XCTAssertNil(snapshot.primaryTask)
    }

    func testStructuredItemLifecycleTracksThinkingAfterCommand() {
        func item(_ eventType: String, _ itemType: String) -> RolloutEvent {
            event(type: "event_msg", text: "", payload: ["payload": .object([
                "type": .string(eventType), "item": .object(["type": .string(itemType)])
            ])])
        }
        XCTAssertEqual(ActivityClassifier.classify(item("item_started", "CommandExecution")), .running)
        XCTAssertEqual(ActivityClassifier.classify(item("item_completed", "CommandExecution")), .thinking)
        XCTAssertEqual(ActivityClassifier.classify(item("item_completed", "Reasoning")), .thinking)
        XCTAssertEqual(ActivityClassifier.classify(item("item_completed", "AgentMessage")), .writing)
    }

    @MainActor
    func testCompactStatusFlipEndpointsAndReducedMotion() {
        let outgoingStart = StatusFlipFrame(progress: 0, entering: false, reduceMotion: false)
        let outgoingMiddle = StatusFlipFrame(progress: 0.25, entering: false, reduceMotion: false)
        let outgoingEnd = StatusFlipFrame(progress: 1, entering: false, reduceMotion: false)
        let incomingStart = StatusFlipFrame(progress: 0, entering: true, reduceMotion: false)
        let incomingMiddle = StatusFlipFrame(progress: 0.75, entering: true, reduceMotion: false)
        let incomingEnd = StatusFlipFrame(progress: 1, entering: true, reduceMotion: false)
        let scales = (outgoingStart.verticalScale, outgoingEnd.verticalScale,
                      incomingStart.verticalScale, incomingEnd.verticalScale)
        let middleBlur = (outgoingMiddle.blurRadius, incomingMiddle.blurRadius)
        let middleScales = (outgoingMiddle.verticalScale, incomingMiddle.verticalScale)
        let crossover = (StatusFlipFrame(progress: 0.5, entering: false, reduceMotion: false).alpha,
                         StatusFlipFrame(progress: 0.5, entering: true, reduceMotion: false).alpha)
        let alphas = (outgoingEnd.alpha, incomingEnd.alpha)
        XCTAssertEqual(IslandDesign.statusFlipDuration, 0.28)
        XCTAssertEqual(IslandDesign.statusFadeDuration, 0.18)
        XCTAssertEqual(scales.0, 1)
        XCTAssertEqual(middleBlur.0, 3, accuracy: 0.001)
        XCTAssertEqual(middleBlur.1, 3, accuracy: 0.001)
        let earlyBlur = StatusFlipFrame(progress: 0.15, entering: false, reduceMotion: false).blurRadius
        let lateBlur = StatusFlipFrame(progress: 0.35, entering: false, reduceMotion: false).blurRadius
        XCTAssertEqual(earlyBlur, 3, accuracy: 0.001)
        XCTAssertEqual(lateBlur, 3, accuracy: 0.001)
        let visibleBlurAlpha = (outgoingMiddle.alpha, incomingMiddle.alpha)
        XCTAssertEqual(visibleBlurAlpha.0, 1)
        XCTAssertEqual(visibleBlurAlpha.1, 1)
        XCTAssertEqual(middleScales.0, 0.54, accuracy: 0.001)
        XCTAssertEqual(middleScales.1, 0.54, accuracy: 0.001)
        XCTAssertEqual(crossover.0, 0)
        XCTAssertEqual(crossover.1, 0)
        XCTAssertEqual(scales.1, 0.08, accuracy: 0.001)
        XCTAssertEqual(scales.2, 0.08, accuracy: 0.001)
        XCTAssertEqual(scales.3, 1)
        XCTAssertEqual(alphas.0, 0)
        XCTAssertEqual(alphas.1, 1)

        let reduced = StatusFlipFrame(progress: 0.5, entering: true, reduceMotion: true)
        let reducedValues = (reduced.verticalScale, reduced.blurRadius, reduced.alpha)
        XCTAssertEqual(reducedValues.0, 1)
        XCTAssertEqual(reducedValues.1, 0)
        XCTAssertEqual(reducedValues.2, 0.5)
    }

    func testQuestionOnlyResolvesForMatchingToolCall() {
        let arguments = #"{"questions":[{"id":"theme","question":"Choose","options":[{"label":"Dark"}]}]}"#
        let request = event(type: "response_item", text: "", payload: ["payload": .object([
            "type": .string("function_call"), "name": .string("request_user_input"),
            "call_id": .string("call-1"), "arguments": .string(arguments)
        ])])
        let unrelated = event(type: "response_item", text: "", payload: ["payload": .object([
            "type": .string("function_call_output"), "call_id": .string("call-2")
        ])])
        let answer = event(type: "response_item", text: "", payload: ["payload": .object([
            "type": .string("function_call_output"), "call_id": .string("call-1")
        ])])
        var value = task()
        var reducer = TaskReducer()
        reducer.reduce(task: &value, events: [request, unrelated])
        XCTAssertEqual(value.pendingQuestion?.id, "theme")
        XCTAssertEqual(value.state, .waitingForInput)
        reducer.reduce(task: &value, events: [answer])
        XCTAssertNil(value.pendingQuestion)
        XCTAssertEqual(value.state, .thinking)
    }

    func testPartialAndMalformedJSONLHandling() {
        var tailer = IncrementalJSONLTailer()
        var lines = tailer.consume(Data("{\"type\":\"start\"}\n{\"type\":".utf8))
        XCTAssertEqual(lines.count, 1)
        XCTAssertNotNil(RolloutParser.parse(line: lines[0]))
        lines = tailer.consume(Data("\"done\"}\nnot json\n".utf8))
        XCTAssertEqual(lines.count, 2)
        XCTAssertNotNil(RolloutParser.parse(line: lines[0]))
        XCTAssertNil(RolloutParser.parse(line: lines[1]))
    }

    func testInitialFileTailIsBoundedAndSkipsPartialLine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexIslandTests-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        var data = Data(repeating: 0x78, count: Int(IncrementalJSONLTailer.initialReadLimit + 20))
        data.append(Data("\n{\"type\":\"task_complete\"}\n".utf8))
        try data.write(to: url)
        var tailer = IncrementalJSONLTailer()
        let lines = try tailer.readNewLines(at: url)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(RolloutParser.parse(line: lines[0])?.type, "task_complete")
        XCTAssertEqual(tailer.offset, UInt64(data.count))
    }

    func testTerminalTransitions() {
        for (text, expected) in [
            ("task_complete", ActivityState.completed),
            ("fatal error", .failed),
            ("turn cancelled", .cancelled)
        ] {
            var value = task(state: .running)
            var reducer = TaskReducer()
            reducer.reduce(task: &value, events: [event(text: text)])
            XCTAssertEqual(value.state, expected)
        }
    }

    func testPendingQuestionExtraction() throws {
        let arguments = #"{"questions":[{"id":"theme","header":"Theme","question":"Choose a theme","options":[{"label":"Dark","description":"Use dark colors"},{"label":"Light","description":"Use light colors"}]}]}"#
        let parsed = event(
            type: "function_call",
            text: "request_user_input \(arguments)",
            payload: ["name": .string("request_user_input"), "arguments": .string(arguments)]
        )
        let question = try XCTUnwrap(TaskReducer.extractQuestion(from: parsed))
        XCTAssertEqual(question.id, "theme")
        XCTAssertEqual(question.choices.map(\.label), ["Dark", "Light"])
    }

    func testDuplicateAnswerPrevention() {
        var reducer = TaskReducer()
        XCTAssertTrue(reducer.markSubmissionStarted(questionID: "q1"))
        XCTAssertFalse(reducer.markSubmissionStarted(questionID: "q1"))
    }

    func testDailyStatAggregation() {
        var first = task(id: "one", state: .completed)
        first.startedAt = now.addingTimeInterval(-3600)
        first.updatedAt = now.addingTimeInterval(-1800)
        first.activityIntervals = [.init(start: first.startedAt!, end: first.updatedAt)]
        first.completedTurns = [now.addingTimeInterval(-1700), now.addingTimeInterval(-90000)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let stats = SnapshotAggregator.dailyStats(tasks: [first], now: now, calendar: calendar)
        XCTAssertEqual(stats.completedTurns, 1)
        XCTAssertEqual(stats.activeDuration, 1800, accuracy: 0.1)
    }

    func testOverlappingAgentTimeIsNotDoubleCounted() {
        var first = task(id: "first")
        var second = task(id: "second")
        first.activityIntervals = [.init(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1200))]
        second.activityIntervals = [.init(start: now.addingTimeInterval(-2400), end: now)]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let stats = SnapshotAggregator.dailyStats(tasks: [first, second], now: now, calendar: calendar)
        XCTAssertEqual(stats.activeDuration, 3600, accuracy: 0.1)
    }

    func testTurnIntervalsCloseOnCompletionAndResume() {
        var item = task()
        var reducer = TaskReducer()
        reducer.reduce(task: &item, events: [
            event(type: "event_msg", text: "", payload: ["payload": .object(["type": .string("task_started")])], timestamp: now.addingTimeInterval(-60)),
            event(type: "event_msg", text: "", payload: ["payload": .object(["type": .string("task_complete")])], timestamp: now.addingTimeInterval(-30)),
            event(type: "event_msg", text: "", payload: ["payload": .object(["type": .string("task_started")])], timestamp: now.addingTimeInterval(-10))
        ])
        XCTAssertEqual(item.activityIntervals.count, 2)
        XCTAssertEqual(item.activityIntervals[0].end, now.addingTimeInterval(-30))
        XCTAssertNil(item.activityIntervals[1].end)
    }

    func testCleanedTitleRemovesMarkdownFence() {
        var item = task()
        item.title = "```text\nBuild Codex Island\n```"
        XCTAssertEqual(item.cleanedTitle, "Build Codex Island")
    }

    func testQuotaSelectsLongestWindow() {
        let short = event(text: "rate limits", payload: [
            "rate_limits": .object(["used_percent": .number(10), "window_minutes": .number(300)])
        ])
        let long = event(text: "rate limits", payload: [
            "rate_limits": .object(["used_percent": .number(25), "window_minutes": .number(10_080)])
        ])
        XCTAssertEqual(TaskReducer.extractQuota(from: short)?.windowMinutes, 300)
        XCTAssertEqual(TaskReducer.extractQuota(from: long)?.windowMinutes, 10_080)
        var one = task(id: "one")
        var two = task(id: "two")
        one.quota = TaskReducer.extractQuota(from: short)
        two.quota = TaskReducer.extractQuota(from: long)
        XCTAssertEqual(SnapshotAggregator.quota(tasks: [one, two], now: now)?.usedPercent, 25)
    }

    func testQuotaPrefersNewestReportNotMostRecentlyActiveTask() {
        var oldTask = task(id: "old", updated: now)
        oldTask.quota = .init(usedPercent: 35, windowMinutes: 10_080,
                              resetAt: now.addingTimeInterval(86_400),
                              observedAt: now.addingTimeInterval(-7_200))
        var newTask = task(id: "new", updated: now.addingTimeInterval(-1_800))
        newTask.quota = .init(usedPercent: 17, windowMinutes: 10_080,
                              resetAt: now.addingTimeInterval(86_400),
                              observedAt: now.addingTimeInterval(-60))
        XCTAssertEqual(SnapshotAggregator.quota(tasks: [oldTask, newTask], now: now)?.remainingPercent, 83)
    }

    func testQuotaParsesNumericResetAndRejectsExpiredReports() {
        let reset = now.addingTimeInterval(3_600)
        let report = event(type: "event_msg", text: "", payload: ["payload": .object([
            "type": .string("token_count"),
            "rate_limits": .object(["primary": .object([
                "used_percent": .number(17), "window_minutes": .number(10_080),
                "resets_at": .number(reset.timeIntervalSince1970)
            ])])
        ])])
        let parsed = TaskReducer.extractQuota(from: report)
        XCTAssertEqual(parsed?.remainingPercent, 83)
        XCTAssertEqual(parsed?.resetAt, reset)
        var item = task()
        item.quota = parsed
        XCTAssertEqual(SnapshotAggregator.quota(tasks: [item], now: now)?.remainingPercent, 83)
        XCTAssertNil(SnapshotAggregator.quota(tasks: [item], now: reset))
    }

    func testQuotaPercentFieldIsNotMistakenForFractionAndIgnoresQuotedData() {
        let percent = event(text: "", payload: ["rate_limits": .object([
            "used_percent": .number(0.5), "window_minutes": .number(300)
        ])])
        XCTAssertEqual(TaskReducer.extractQuota(from: percent)?.usedPercent, 0.5)
        let utilization = event(text: "", payload: ["rate_limits": .object([
            "utilization": .number(0.5), "window_minutes": .number(300)
        ])])
        XCTAssertEqual(TaskReducer.extractQuota(from: utilization)?.usedPercent, 50)
        let quoted = event(type: "response_item", text: "", payload: ["payload": .object([
            "type": .string("message"), "used_percent": .number(35),
            "window_minutes": .number(10_080)
        ])])
        XCTAssertNil(TaskReducer.extractQuota(from: quoted))
    }

    func testLayoutCalculations() {
        let layout = IslandLayout.calculate(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTopInset: 38, leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
            calibration: .init(horizontalOffset: 10, widthAdjustment: 20)
        )
        XCTAssertEqual(layout.notchGapWidth, 192)
        XCTAssertEqual(layout.compactFrame.height, 38)
        XCTAssertEqual(layout.compactFrame.midX, 766)
        XCTAssertEqual(layout.expandedFrame.maxY, 982)
        XCTAssertEqual(layout.previewFrame.height, 154)
        XCTAssertEqual(layout.shoulderReach, 100)
        XCTAssertEqual(layout.compactFrame.width, 742)
        XCTAssertEqual(layout.bodyWidth(at: 0), 438)
        XCTAssertEqual(layout.previewFrame.width, 838)
        XCTAssertEqual(layout.bodyWidth(at: 1), 638)
        XCTAssertEqual(layout.expandedFrame.width, 902)
        XCTAssertEqual(layout.bodyWidth(at: 2), 702)
        XCTAssertEqual(layout.expandedFrame.height, 480)
    }

    func testCompactWidthContractsAndExpandsForContent() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func layout(cubes: Int, statusWidth: CGFloat) -> IslandLayout {
            IslandLayout.calculate(screenFrame: screen, safeTopInset: 38,
                                   leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                                   calibration: .init(),
                                   compactWingWidth: CompactRailSizing.wingWidth(
                                    cubeCount: cubes, statusTextWidth: statusWidth))
        }
        let idle = layout(cubes: 1, statusWidth: 35)
        let three = layout(cubes: 3, statusWidth: 35)
        let four = layout(cubes: 4, statusWidth: 35)
        let longLabel = layout(cubes: 1, statusWidth: 85)
        XCTAssertLessThan(idle.compactFrame.width, three.compactFrame.width)
        XCTAssertLessThan(three.compactFrame.width, four.compactFrame.width)
        XCTAssertGreaterThan(longLabel.compactFrame.width, idle.compactFrame.width)
        XCTAssertLessThan(idle.bodyWidth(at: 0), 400)
        for item in [idle, three, four, longLabel] {
            XCTAssertGreaterThanOrEqual(item.bodyWidth(at: 0), item.notchGapWidth + 2 * 76)
            XCTAssertGreaterThanOrEqual(item.previewFrame.width, item.compactFrame.width)
            XCTAssertGreaterThanOrEqual(item.expandedFrame.width, item.previewFrame.width)
            XCTAssertEqual(item.compactFrame.midX, screen.midX, accuracy: 0.001)
            XCTAssertEqual(item.compactFrame.height, 38)
        }
    }

    func testAdaptiveWidthOverridesSavedManualExpansionWithoutDiscardingIt() throws {
        let legacy = Data(#"{"horizontalOffset":-1,"shoulderReach":36,"widthAdjustment":120}"#.utf8)
        var calibration = try JSONDecoder().decode(Calibration.self, from: legacy)
        XCTAssertTrue(calibration.adaptiveWidth)
        XCTAssertEqual(calibration.widthAdjustment, 120)
        let wing = CompactRailSizing.wingWidth(cubeCount: 1, statusTextWidth: 48)
        func layout() -> IslandLayout {
            IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   safeTopInset: 38, leftAuxiliaryMaxX: 660,
                                   rightAuxiliaryMinX: 852, calibration: calibration,
                                   compactWingWidth: wing)
        }
        let adaptive = layout()
        calibration.adaptiveWidth = false
        let manual = layout()
        XCTAssertEqual(adaptive.shoulderReach, 36)
        XCTAssertEqual(manual.shoulderReach, 36)
        XCTAssertGreaterThan(manual.compactFrame.width, adaptive.compactFrame.width)
        XCTAssertGreaterThanOrEqual(manual.expandedFrame.width, adaptive.expandedFrame.width)
    }

    @MainActor
    func testCompactWidthSpringReversesWithoutJumping() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func layout(_ wing: CGFloat) -> IslandLayout {
            IslandLayout.calculate(screenFrame: screen, safeTopInset: 38,
                                   leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                                   calibration: .init(), compactWingWidth: wing)
        }
        let small = layout(70)
        let large = layout(105)
        let coordinator = IslandMotionCoordinator(layout: small)
        coordinator.update(layout: large, state: .compact, policy: .full)
        XCTAssertEqual(coordinator.frame.width, small.compactFrame.width)
        for _ in 0..<6 { coordinator.advance(by: 1.0 / 60) }
        let position = coordinator.frame.width
        let velocity = coordinator.widthSpring.velocity
        XCTAssertGreaterThan(position, small.compactFrame.width)
        XCTAssertLessThan(position, large.compactFrame.width)
        coordinator.update(layout: small, state: .compact, policy: .full)
        XCTAssertEqual(coordinator.frame.width, position)
        XCTAssertEqual(coordinator.widthSpring.velocity, velocity)
        for _ in 0..<120 { coordinator.advance(by: 1.0 / 60) }
        XCTAssertEqual(coordinator.frame.width, small.compactFrame.width, accuracy: 0.001)
        XCTAssertTrue(coordinator.widthSpring.isSettled)
        coordinator.update(layout: large, state: .compact, policy: .reduced)
        XCTAssertEqual(coordinator.frame.width, large.compactFrame.width)
        XCTAssertTrue(coordinator.widthSpring.isSettled)
    }

    func testLayoutTrajectoryIsContinuousAndBounded() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let layout = IslandLayout.calculate(screenFrame: screen, safeTopInset: 38,
                                           leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                                           calibration: .init(horizontalOffset: 10, widthAdjustment: 20))
        XCTAssertEqual(layout.frame(at: 0), layout.compactFrame)
        XCTAssertEqual(layout.frame(at: 1), layout.previewFrame)
        XCTAssertEqual(layout.frame(at: 2), layout.expandedFrame)
        let epsilon = 0.0001
        let left = layout.frame(at: 1 - epsilon)
        let middle = layout.frame(at: 1)
        let right = layout.frame(at: 1 + epsilon)
        for coordinate: (CGRect) -> CGFloat in [{ $0.minX }, { $0.width }, { $0.height }] {
            let leftSlope = (coordinate(middle) - coordinate(left)) / epsilon
            let rightSlope = (coordinate(right) - coordinate(middle)) / epsilon
            XCTAssertEqual(leftSlope, rightSlope, accuracy: 0.1)
        }
        for step in 0...200 {
            let frame = layout.frame(at: Double(step) / 100)
                XCTAssertGreaterThanOrEqual(frame.width, layout.compactFrame.width - 0.000001)
                XCTAssertLessThanOrEqual(frame.width, layout.expandedFrame.width + 0.000001)
            XCTAssertGreaterThanOrEqual(frame.height, layout.compactFrame.height)
            XCTAssertLessThanOrEqual(frame.height, layout.expandedFrame.height)
            XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.0001)
        }
    }

    func testLayoutTrajectoryKeepsCenterAndScreenEdgeAlignment() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for offset in [0.0, 600.0] {
            let layout = IslandLayout.calculate(screenFrame: screen, safeTopInset: 38,
                                               leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                                               calibration: .init(horizontalOffset: offset))
            for step in 0...200 {
                let frame = layout.frame(at: Double(step) / 100)
                if offset == 0 {
                    XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.000001)
                } else {
                    XCTAssertEqual(frame.maxX, screen.maxX, accuracy: 0.000001)
                }
            }
            let epsilon = 0.0001
            let left = layout.frame(at: 1 - epsilon)
            let middle = layout.frame(at: 1)
            let right = layout.frame(at: 1 + epsilon)
            let leftSlope = (middle.minX - left.minX) / epsilon
            let rightSlope = (right.minX - middle.minX) / epsilon
            XCTAssertEqual(leftSlope, rightSlope, accuracy: 0.1)
        }
    }

    func testCompactQuotaRingThresholdAndUnavailableState() {
        func quota(_ used: Double) -> QuotaWindow {
            .init(usedPercent: used, windowMinutes: 10080, resetAt: nil)
        }
        XCTAssertEqual(CompactQuotaState(quota: quota(0)).displayText, "100")
        XCTAssertEqual(CompactQuotaState(quota: quota(7)).displayText, "93")
        XCTAssertFalse(CompactQuotaState(quota: quota(75)).isCritical)
        XCTAssertTrue(CompactQuotaState(quota: quota(75.01)).isCritical)
        XCTAssertEqual(CompactQuotaState(quota: quota(75.01)).displayText, "24")
        XCTAssertTrue(CompactQuotaState(quota: quota(100)).isCritical)
        XCTAssertEqual(CompactQuotaState(quota: quota(100)).fraction, 0)
        XCTAssertNil(CompactQuotaState(quota: nil).percentage)
        XCTAssertEqual(CompactQuotaState(quota: nil).displayText, "–")
        XCTAssertEqual(CompactQuotaState(quota: nil).accessibilityLabel, "Codex quota unavailable")
        XCTAssertNil(CompactQuotaState(quota: quota(.nan)).percentage)
    }

    @MainActor
    func testCompactQuotaRingLeavesVerticalNotchClearance() {
        for notchHeight: CGFloat in [32, 38] {
            XCTAssertGreaterThanOrEqual((notchHeight - CompactQuotaRing.diameter) / 2, 6)
        }
        XCTAssertEqual(CompactQuotaRing.strokeWidth, 1.2)
        XCTAssertEqual(CompactQuotaRing.numberSize(for: 83, preferredSize: 8.5), 8.5)
        XCTAssertEqual(CompactQuotaRing.numberSize(for: 100, preferredSize: 8.5), 7)
        XCTAssertEqual(CompactQuotaRing.numberSize(for: 84, preferredSize: 10), 10)
    }

    @MainActor
    func testBundledNunitoFontsRegister() {
        IslandFont.register()
        XCTAssertTrue(IslandFont.isAvailable)
        XCTAssertTrue(IslandFont.isLightAvailable)
        XCTAssertTrue(IslandFont.isRegularAvailable)
        XCTAssertEqual(IslandFont.postScriptName, "Nunito-SemiBold")
        XCTAssertEqual(IslandFont.lightPostScriptName, "Nunito-Light")
        XCTAssertEqual(IslandFont.regularPostScriptName, "Nunito-Regular")
        XCTAssertNotNil(NSFont(name: IslandFont.postScriptName, size: 8))
        XCTAssertNotNil(NSFont(name: IslandFont.lightPostScriptName, size: 12))
        XCTAssertNotNil(NSFont(name: IslandFont.regularPostScriptName, size: 12))
    }

    @MainActor
    func testPenpotTrayFontUsesRealVariableWeightsWithoutChangingRailFont() {
        IslandFont.register()
        XCTAssertTrue(TrayFont.isAvailable)
        for (weight, expected) in [(SwiftUI.Font.Weight.regular, 400), (.medium, 500), (.semibold, 600)] {
            let font = TrayFont.nsFont(size: 11, weight: weight)
            XCTAssertEqual(font.familyName, "Inter Tight")
            let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
            // CoreText omits the variation dictionary at the font's default (400) weight.
            XCTAssertEqual(variations?[NSNumber(value: 0x77676874)]?.intValue ?? 400, expected)
        }
        XCTAssertEqual(IslandFont.nsFont(weight: .regular, size: 13).familyName, "Nunito")
    }

    func testCompactTypographyPersistsAndClampsSizes() throws {
        let suite = "CodexIslandTypographyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let choice = CompactTypography(statusSize: 13.5, statusWeight: .semibold,
                                       quotaSize: 9.5, quotaWeight: .light)
        choice.save(to: defaults)
        XCTAssertEqual(CompactTypography.load(from: defaults), choice)
        CompactTypography(statusSize: 100, quotaSize: -1).save(to: defaults)
        XCTAssertEqual(CompactTypography.load(from: defaults).statusSize, 14)
        XCTAssertEqual(CompactTypography.load(from: defaults).quotaSize, 7.5)
    }

    @MainActor
    func testTypographyChangeRecomputesCompactWidth() async {
        IslandFont.register()
        let small = CompactTypography(statusSize: 10)
        let large = CompactTypography(statusSize: 14)
        let narrow = PanelController.compactWingWidth(cubeCount: 1, statusLabel: "Thinking",
                                                      typography: small)
        let wide = PanelController.compactWingWidth(cubeCount: 1, statusLabel: "Thinking",
                                                    typography: large)
        XCTAssertGreaterThan(wide, narrow)
        let model = AppModel(fixture: IslandFixtures.snapshot("idle"))
        var updated = false
        model.onLayoutChange = { updated = true }
        model.typography.statusSize = 13
        await Task.yield()
        XCTAssertTrue(updated)
    }

    func testCompactStatusGapIsIncludedInAdaptiveWidth() {
        let textWidth: CGFloat = 75
        let wing = CompactRailSizing.wingWidth(cubeCount: 1, statusTextWidth: textWidth)
        XCTAssertEqual(CompactRailSizing.statusGap, 9)
        XCTAssertEqual(wing, textWidth + CompactRailSizing.statusGap
                       + CompactRailSizing.quotaDiameter + 2 * CompactRailSizing.statusSideInset)
        XCTAssertGreaterThanOrEqual(CompactRailSizing.statusSideInset, 8)
    }

    func testPresentationStateTransitions() {
        var state = PresentationState.compact
        state.hover(true)
        XCTAssertEqual(state, .preview)
        state.hover(false)
        XCTAssertEqual(state, .compact)
        state.click()
        XCTAssertEqual(state, .pinned)
        state.hover(false)
        XCTAssertEqual(state, .pinned)
        state.dismiss()
        XCTAssertEqual(state, .compact)
    }

    @MainActor
    func testHoverExitUsesGracePeriodAndReentryCancelsCollapse() async throws {
        let model = AppModel()
        model.hover(true)
        XCTAssertEqual(model.presentation, .compact)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.presentation, .preview)
        model.hover(false)
        XCTAssertEqual(model.presentation, .preview)

        try await Task.sleep(for: .milliseconds(80))
        model.hover(true)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(model.presentation, .preview)

        model.hover(false)
        try await Task.sleep(for: .milliseconds(260))
        XCTAssertEqual(model.presentation, .compact)
    }

    @MainActor
    func testDismissRequiresPointerExitAndPinningIsIdempotent() async throws {
        let model = AppModel(fixture: IslandFixtures.snapshot("active"))
        model.hover(true)
        model.clickIsland()
        model.clickIsland()
        model.page = .recent
        XCTAssertEqual(model.presentation, .pinned)
        model.dismiss()
        model.hover(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.presentation, .compact)
        XCTAssertEqual(model.page, .activity)
        model.hover(false)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.presentation, .preview)
    }

    @MainActor
    func testBriefHoverDoesNotOpen() async throws {
        let model = AppModel(fixture: IslandFixtures.snapshot("idle"))
        model.hover(true)
        model.hover(false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.presentation, .compact)
    }

    func testSpringReversalPreservesPositionAndSettles() {
        var spring = IslandSpring(target: 2)
        for _ in 0..<6 { spring.advance(by: 1.0 / 60) }
        let position = spring.value
        let velocity = spring.velocity
        spring.target = 0
        XCTAssertEqual(spring.value, position)
        XCTAssertEqual(spring.velocity, velocity)
        for _ in 0..<120 { spring.advance(by: 1.0 / 60) }
        XCTAssertTrue(spring.isSettled)
        XCTAssertEqual(spring.value, 0)
    }

    func testContentRevealRoutesAndOverlap() {
        XCTAssertEqual(IslandContentReveal.previewOpacity(0.90, eligible: true), 1, accuracy: 0.0001)
        XCTAssertEqual(IslandContentReveal.previewOpacity(1, eligible: false), 0)
        XCTAssertEqual(IslandContentReveal.previewOpacity(1.45, eligible: true), 0, accuracy: 0.0001)
        XCTAssertEqual(IslandContentReveal.expandedOpacity(1.80, previewEligible: true), 1,
                       accuracy: 0.0001)
        XCTAssertEqual(IslandContentReveal.expandedOpacity(1.65, previewEligible: false), 1,
                       accuracy: 0.0001)
        for step in 110...180 {
            let progress = Double(step) / 100
            let preview = IslandContentReveal.previewOpacity(progress, eligible: true)
            let expanded = IslandContentReveal.expandedOpacity(progress, previewEligible: true)
            XCTAssertLessThan(min(preview, expanded), 0.20, "Overlapping content at \(progress)")
        }
        XCTAssertEqual(IslandContentReveal.previewYOffset(0.5, opacity: 0.5, movementAllowed: false), 0)
        XCTAssertEqual(IslandContentReveal.previewYOffset(1.3, opacity: 0.5, movementAllowed: false), 0)
        XCTAssertEqual(IslandContentReveal.expandedYOffset(opacity: 0.5, movementAllowed: false), 0)
        XCTAssertEqual(IslandContentReveal.previewYOffset(0.5, opacity: 0.5, movementAllowed: true), 3)
        XCTAssertEqual(IslandContentReveal.previewYOffset(1.3, opacity: 0.5, movementAllowed: true), -2)
        XCTAssertEqual(IslandContentReveal.expandedYOffset(opacity: 0.5, movementAllowed: true), 3)
    }

    @MainActor
    func testContentEligibilityPreservesSpringDuringRouteChanges() {
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                           safeTopInset: 38, leftAuxiliaryMaxX: 660,
                                           rightAuxiliaryMinX: 852, calibration: .init())
        let direct = IslandMotionCoordinator(layout: layout)
        direct.update(layout: layout, state: .pinned, policy: .full)
        XCTAssertFalse(direct.previewContentEligible)
        direct.advance(by: 1.0 / 60)
        let directValue = direct.spring.value
        let directVelocity = direct.spring.velocity
        direct.update(layout: layout, state: .compact, policy: .full)
        XCTAssertFalse(direct.previewContentEligible)
        XCTAssertEqual(direct.spring.value, directValue)
        XCTAssertEqual(direct.spring.velocity, directVelocity)

        let hover = IslandMotionCoordinator(layout: layout)
        hover.update(layout: layout, state: .preview, policy: .full)
        XCTAssertTrue(hover.previewContentEligible)
        for _ in 0..<15 { hover.advance(by: 1.0 / 60) }
        XCTAssertGreaterThanOrEqual(hover.spring.value, 0.65)
        let hoverValue = hover.spring.value
        let hoverVelocity = hover.spring.velocity
        hover.update(layout: layout, state: .pinned, policy: .full)
        XCTAssertTrue(hover.previewContentEligible)
        XCTAssertEqual(hover.spring.value, hoverValue)
        XCTAssertEqual(hover.spring.velocity, hoverVelocity)
        hover.update(layout: layout, state: .compact, policy: .full)
        XCTAssertFalse(hover.previewContentEligible)
        XCTAssertEqual(hover.spring.value, hoverValue)
        XCTAssertEqual(hover.spring.velocity, hoverVelocity)

        let early = IslandMotionCoordinator(layout: layout)
        early.update(layout: layout, state: .preview, policy: .full)
        for _ in 0..<3 { early.advance(by: 1.0 / 60) }
        XCTAssertGreaterThan(early.progress, 0.12)
        XCTAssertLessThan(early.progress, 0.65)
        let opacityBeforePin = IslandContentReveal.previewOpacity(early.progress,
                                                                  eligible: early.previewContentEligible)
        early.update(layout: layout, state: .pinned, policy: .full)
        let opacityAfterPin = IslandContentReveal.previewOpacity(early.progress,
                                                                 eligible: early.previewContentEligible)
        XCTAssertGreaterThan(opacityBeforePin, 0)
        XCTAssertEqual(opacityAfterPin, opacityBeforePin)

        let exit = IslandMotionCoordinator(layout: layout)
        exit.update(layout: layout, state: .preview, policy: .full)
        for _ in 0..<15 { exit.advance(by: 1.0 / 60) }
        exit.update(layout: layout, state: .compact, policy: .full)
        XCTAssertTrue(exit.previewContentEligible)
        for _ in 0..<120 { exit.advance(by: 1.0 / 60) }
        XCTAssertEqual(exit.progress, 0)
        XCTAssertFalse(exit.previewContentEligible)
    }

    func testGeometryStaysOnScreenAndCornersPassThrough() {
        let screen = CGRect(x: 800, y: 0, width: 400, height: 360)
        let layout = IslandLayout.calculate(screenFrame: screen, safeTopInset: 28,
                                           leftAuxiliaryMaxX: nil, rightAuxiliaryMinX: nil,
                                           calibration: .init(horizontalOffset: 500, widthAdjustment: 180))
        for p in stride(from: 0.0, through: 2.0, by: 0.1) {
            let frame = layout.frame(at: p)
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
            XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY + 24)
        }
        XCTAssertFalse(IslandHitRegion.contains(.init(x: 1, y: 1), size: .init(width: 456, height: 480),
                                                radius: 26, shoulderReach: layout.shoulderReach,
                                                shoulderHeight: 28, shoulderBlend: 1))
        XCTAssertTrue(IslandHitRegion.contains(.init(x: 200, y: 2), size: .init(width: 456, height: 480),
                                               radius: 26, shoulderReach: layout.shoulderReach,
                                               shoulderHeight: 28, shoulderBlend: 1))
        XCTAssertEqual(layout.compactFrame.height, 28)
    }

    func testShoulderContourMatchesHitTestingAcrossPresentationSizes() {
        for height: CGFloat in [38, 154, 480] {
            let size = CGSize(width: 656, height: height)
            let radius: CGFloat = height == 38 ? 0 : 26
            let shoulderHeight: CGFloat = 38
            let blend: CGFloat = height == 38 ? 0 : 1
            let path = IslandContour.path(size: size, radius: radius,
                                          shoulderReach: 100, shoulderHeight: shoulderHeight,
                                          shoulderBlend: blend)
            XCTAssertEqual(path.boundingBoxOfPath, CGRect(origin: .zero, size: size))
            // Broad shoulder joins the top; transparent area below it passes clicks through.
            XCTAssertTrue(IslandHitRegion.contains(.init(x: 20, y: height - 0.025), size: size,
                                                   radius: radius, shoulderReach: 100,
                                                   shoulderHeight: shoulderHeight, shoulderBlend: blend))
            XCTAssertFalse(IslandHitRegion.contains(.init(x: 25, y: height - 10), size: size,
                                                    radius: radius, shoulderReach: 100,
                                                    shoulderHeight: shoulderHeight, shoulderBlend: blend))
            XCTAssertTrue(IslandHitRegion.contains(.init(x: 110, y: height - 28), size: size,
                                                   radius: radius, shoulderReach: 100,
                                                   shoulderHeight: shoulderHeight, shoulderBlend: blend))
            for x in stride(from: CGFloat(0.5), to: size.width, by: 5) {
                for y in stride(from: CGFloat(0.5), to: height, by: 5) {
                    let hit = IslandHitRegion.contains(.init(x: x, y: y), size: size, radius: radius,
                                                       shoulderReach: 100, shoulderHeight: shoulderHeight,
                                                       shoulderBlend: blend)
                    XCTAssertEqual(hit, path.contains(.init(x: x, y: height - y)))
                    XCTAssertEqual(hit, IslandHitRegion.contains(.init(x: size.width - x, y: y), size: size,
                                                                 radius: radius, shoulderReach: 100,
                                                                 shoulderHeight: shoulderHeight, shoulderBlend: blend))
                }
            }
        }
    }

    func testCubeIdentityAndPhaseSurviveRefreshAndOperationChanges() {
        var roster = CubeRoster()
        var a = task(id: "a", state: .thinking)
        let b = task(id: "b", state: .editing)
        let first = roster.reconcile(tasks: [a, b], now: now)
        a.state = .running
        a.updatedAt = now.addingTimeInterval(2)
        let second = roster.reconcile(tasks: [b, a], now: now.addingTimeInterval(2))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map(\.epoch), second.map(\.epoch))
        XCTAssertEqual(first.map(\.seed), second.map(\.seed))
    }

    func testOneCubePerActiveChatDespiteSubagents() {
        var roster = CubeRoster()
        let roots = (1...3).map { task(id: "chat\($0)", state: .running) }
        let children = (1...3).map { index -> TaskSnapshot in
            var child = task(id: "agent\(index)", state: .editing, child: true)
            child.rootChatID = "chat\(index)"
            return child
        }
        let first = roster.reconcile(tasks: roots + children, now: now)
        XCTAssertEqual(first.map(\.id), roots.map(\.id))
        let second = roster.reconcile(tasks: children.reversed() + roots.reversed(), now: now.addingTimeInterval(1))
        XCTAssertEqual(second.map(\.id), first.map(\.id))
        XCTAssertEqual(second.map(\.seed), first.map(\.seed))
    }

    func testChildActivityUsesParentCubeWithoutChildCompletionFill() {
        var roster = CubeRoster()
        let root = task(id: "chat", state: .idle)
        var child = task(id: "agent", state: .thinking, child: true)
        child.rootChatID = root.id
        let active = roster.reconcile(tasks: [root, child], now: now)
        XCTAssertEqual(active.map(\.id), ["chat"])
        XCTAssertEqual(active[0].state, .thinking)
        child.state = .completed
        let afterChild = roster.reconcile(tasks: [root, child], now: now.addingTimeInterval(1))
        XCTAssertEqual(afterChild.map(\.id), ["idle"])
        XCTAssertEqual(afterChild[0].solvedColor, 0)
    }

    func testChildWithKnownParentButMissingParentRowUsesParentIdentity() {
        var roster = CubeRoster()
        var child = task(id: "agent", state: .running, child: true)
        child.rootChatID = "chat"
        XCTAssertEqual(roster.reconcile(tasks: [child], now: now).map(\.id), ["chat"])
        child.rootChatID = nil
        XCTAssertEqual(roster.reconcile(tasks: [child], now: now).map(\.id), ["idle"])
    }

    func testThreadLineageParsesAndRejectsUnknownOrCyclicParents() {
        let source = #"{"subagent":{"thread_spawn":{"parent_thread_id":"parent"}}}"#
        XCTAssertEqual(ThreadLineage.parentID(in: source), "parent")
        XCTAssertNil(ThreadLineage.parentID(in: #"{"subagent":{"other":"guardian"}}"#))
        XCTAssertEqual(ThreadLineage.rootID(for: "leaf", parents: ["leaf": "middle", "middle": "root"]), "root")
        XCTAssertNil(ThreadLineage.rootID(for: "leaf", parents: [:]))
        XCTAssertNil(ThreadLineage.rootID(for: "leaf", parents: ["leaf": "middle", "middle": "leaf"]))
    }

    func testFirstSolvedCubeIsGreenRegardlessOfEarlierSeeds() {
        var roster = CubeRoster()
        _ = roster.reconcile(tasks: [task(id: "earlier", state: .running)], now: now)
        _ = roster.reconcile(tasks: [], now: now)
        let done = [task(id: "a", state: .completed), task(id: "b", state: .completed),
                    task(id: "c", state: .completed)]
        let cubes = roster.reconcile(tasks: done, now: now)
        XCTAssertEqual(cubes.map(\.solvedColor), [0, 1, 2])
        XCTAssertEqual(roster.reconcile(tasks: Array(done.reversed()), now: now).map(\.solvedColor), [0, 1, 2])
        XCTAssertEqual(roster.reconcile(tasks: done, now: now.addingTimeInterval(4))[0].solvedColor, 0)
        XCTAssertEqual(CubeDescriptor.idle.solvedColor, 0)
    }

    func testResumingCompletedChatRestoresActiveFace() {
        var roster = CubeRoster()
        _ = roster.reconcile(tasks: [task(state: .completed)], now: now)
        let resumed = roster.reconcile(tasks: [task(state: .running)], now: now.addingTimeInterval(1))[0]
        XCTAssertNil(resumed.solvedColor)
        XCTAssertTrue(CubeTimeline.animates(resumed, at: now, enabled: true, visible: true))
    }

    func testCubeCompletionSettlesAndAnimationPolicyStopsIdleWork() {
        var roster = CubeRoster()
        let completed = task(id: "finished", state: .completed)
        let cube = roster.reconcile(tasks: [completed], now: now)[0]
        XCTAssertTrue(CubeTimeline.animates(cube, at: now, enabled: true, visible: true))
        XCTAssertFalse(CubeTimeline.animates(cube, at: now.addingTimeInterval(0.5), enabled: true, visible: true))
        for index in 0..<9 { XCTAssertEqual(CubeTimeline.completion(index: index, elapsed: 0.49), 1, accuracy: 0.0001) }
        let settled = roster.reconcile(tasks: [completed], now: now.addingTimeInterval(4))[0]
        XCTAssertEqual(settled.state, .idle)
        XCTAssertEqual(settled.solvedColor, cube.solvedColor)
        XCTAssertFalse(CubeTimeline.animates(settled, at: now, enabled: true, visible: true))
        let active = CubeDescriptor(id: "a", title: "Working", state: .thinking, epoch: now, seed: 1)
        XCTAssertFalse(CubeTimeline.animates(active, at: now, enabled: false, visible: true))
        XCTAssertFalse(CubeTimeline.animates(active, at: now, enabled: true, visible: false))
        XCTAssertEqual(Set(CubeTimeline.order(seed: 3, cycle: 2)), Set(0..<9))
        XCTAssertEqual(CubeTimeline.visibleCount(total: 5, wingWidth: 83), 2)
    }

    @MainActor
    func testImmediateMotionHasNoDriverAndReduceMotionTakesPrecedence() {
        XCTAssertEqual(IslandMotionPolicy.resolve(enabled: true, reduceMotion: true), .reduced)
        XCTAssertEqual(IslandMotionPolicy.resolve(enabled: false, reduceMotion: true), .immediate)
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                           safeTopInset: 32, leftAuxiliaryMaxX: nil,
                                           rightAuxiliaryMinX: nil, calibration: .init())
        let coordinator = IslandMotionCoordinator(layout: layout)
        coordinator.update(layout: layout, state: .pinned, policy: .immediate)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.frame, layout.expandedFrame)
    }

    func testCalibrationPersistence() {
        let suite = "CodexIslandTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let value = Calibration(horizontalOffset: 22, widthAdjustment: -8, shoulderReach: 74)
        value.save(to: defaults)
        XCTAssertEqual(Calibration.load(from: defaults), value)

        defaults.set(Data(#"{"horizontalOffset":22,"widthAdjustment":-8}"#.utf8),
                     forKey: Calibration.defaultsKey)
        XCTAssertEqual(Calibration.load(from: defaults),
                       Calibration(horizontalOffset: 22, widthAdjustment: -8, shoulderReach: 100))
        XCTAssertTrue(Calibration.load(from: defaults).adaptiveWidth)
    }

    func testShoulderCurveCalibrationChangesPanelWidth() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        func layout(_ reach: Double) -> IslandLayout {
            IslandLayout.calculate(screenFrame: screen, safeTopInset: 38,
                                   leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                                   calibration: .init(shoulderReach: reach))
        }
        let narrow = layout(0)
        let broad = layout(140)
        XCTAssertEqual(narrow.shoulderReach, 0)
        XCTAssertEqual(broad.shoulderReach, 140)
        XCTAssertEqual(broad.compactFrame.width - narrow.compactFrame.width, 350)
        XCTAssertEqual(broad.bodyWidth(at: 0), narrow.bodyWidth(at: 0))
        XCTAssertGreaterThanOrEqual(broad.bodyWidth(at: 2), narrow.bodyWidth(at: 2))
    }

    func testReadFailurePreservesSnapshot() {
        var keeper = SnapshotKeeper()
        let good = IslandSnapshot(
            tasks: [task()], primaryTaskID: nil,
            dailyStats: .init(completedTurns: 0, activeDuration: 0),
            quota: nil, refreshedAt: now, errorMessage: nil
        )
        keeper.accept(.success(good))
        keeper.accept(.failure(CodexDataError.databaseMissing), now: now.addingTimeInterval(2))
        XCTAssertEqual(keeper.snapshot.tasks, good.tasks)
        XCTAssertNotNil(keeper.snapshot.errorMessage)
    }
}
