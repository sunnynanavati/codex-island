import Foundation

enum RolloutParser {
    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    static func parse(line: Data) -> RolloutEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return nil }
        let payload = object.mapValues(JSONValue.init)
        let type = firstString(in: object, keys: ["type", "event", "kind"]) ?? "unknown"
        let timestampText = firstString(in: object, keys: ["timestamp", "created_at", "time"])
        let timestamp = timestampText.flatMap(parseDate) ?? Date()
        return RolloutEvent(
            timestamp: timestamp,
            type: type,
            text: flattenedText(object),
            payload: payload
        )
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
        }
        return nil
    }

    static func flattenedText(_ value: Any) -> String {
        var parts: [String] = []
        func walk(_ item: Any) {
            switch item {
            case let string as String: parts.append(string)
            case let dictionary as [String: Any]:
                dictionary.keys.sorted().forEach { key in walk(dictionary[key] as Any) }
            case let array as [Any]: array.forEach(walk)
            default: break
            }
        }
        walk(value)
        return parts.joined(separator: " ").lowercased()
    }
}

struct IncrementalJSONLTailer: Sendable {
    static let initialReadLimit: UInt64 = 512 * 1024
    private(set) var offset: UInt64 = 0
    private(set) var remainder = Data()
    private(set) var initialized = false

    mutating func consume(_ data: Data, fileSize: UInt64? = nil) -> [Data] {
        if let fileSize, fileSize < offset {
            offset = 0
            remainder.removeAll(keepingCapacity: true)
        }
        offset += UInt64(data.count)
        remainder.append(data)
        var lines: [Data] = []
        while let newline = remainder.firstIndex(of: 0x0A) {
            let line = remainder[..<newline]
            remainder.removeSubrange(...newline)
            if !line.isEmpty { lines.append(Data(line)) }
        }
        return lines
    }

    mutating func readNewLines(at url: URL) throws -> [Data] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        if !initialized || size < offset {
            initialized = true
            remainder.removeAll(keepingCapacity: true)
            let start = size > Self.initialReadLimit ? size - Self.initialReadLimit : 0
            offset = start
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: start)
            let data = try handle.readToEnd() ?? Data()
            var lines = consume(data, fileSize: size)
            // A bounded tail usually begins in the middle of a JSON object.
            if start > 0, !lines.isEmpty { lines.removeFirst() }
            return lines
        }
        guard size > offset else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return consume(data, fileSize: size)
    }
}

enum ActivityClassifier {
    static func classify(_ event: RolloutEvent) -> ActivityState {
        let payload = event.payload["payload"]
        let payloadType = payload?.field("type")?.string?.lowercased() ?? ""
        let name = payload?.field("name")?.string?.lowercased() ?? ""
        switch (event.type.lowercased(), payloadType) {
        case ("event_msg", "task_started"): return .starting
        case ("event_msg", "task_complete"): return .completed
        case ("event_msg", "turn_aborted"): return .cancelled
        case ("event_msg", "agent_reasoning"), ("response_item", "reasoning"): return .thinking
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            return .thinking
        case ("event_msg", "item_started"), ("event_msg", "item_completed"):
            let itemType = payload?.field("item")?.field("type")?.string?.lowercased() ?? ""
            if itemType == "reasoning" { return .thinking }
            if itemType == "agentmessage" { return .writing }
            if itemType == "commandexecution" {
                return payloadType == "item_started" ? .running : .thinking
            }
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"):
            if name == "request_user_input" { return .waitingForInput }
            if contains(name, ["apply_patch", "write_file", "edit"]) { return .editing }
            if contains(name, ["search", "web"]) { return .searching }
            if contains(name, ["read_file"]) { return .reading }
            if contains(name, ["list_files"]) { return .scanning }
            if contains(name, ["update_plan", "create_plan"]) { return .planning }
            return .running
        case ("response_item", "message"):
            return payload?.field("role")?.string?.lowercased() == "assistant" ? .writing : .idle
        case ("event_msg", "error"), ("event_msg", "task_failed"): return .failed
        default: break
        }
        // Generic synthetic or older rollout records may store the operation at top level.
        guard event.type == "event" || event.type == "tool_call" else { return .idle }
        let text = event.text
        if contains(text, ["task_complete", "turn.completed"]) { return .completed }
        if contains(text, ["turn cancelled", "turn_aborted"]) { return .cancelled }
        if contains(text, ["fatal error", "task_failed"]) { return .failed }
        if contains(text, ["request_user_input"]) { return .waitingForInput }
        if contains(text, ["apply_patch", "write_file"]) { return .editing }
        if contains(text, ["exec_command", "tool_call"]) { return .running }
        if contains(text, ["assistant_message", "final_answer"]) { return .writing }
        return .idle
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains(where: text.contains)
    }
}

struct TaskReducer: Sendable {
    private(set) var answeredQuestionIDs: Set<String> = []
    private(set) var lastActivityAt: Date?
    private var pendingQuestionCallID: String?
    private var turnEnded = false

    mutating func reduce(task: inout TaskSnapshot, events: [RolloutEvent]) {
        for event in events {
            let classified = ActivityClassifier.classify(event)
            if classified == .starting { turnEnded = false }
            // Late tool and metadata events can arrive after task_complete.
            // They do not start a new turn or reactivate its cube.
            if turnEnded { continue }
            task.updatedAt = max(task.updatedAt, event.timestamp)
            if classified != .idle {
                lastActivityAt = max(lastActivityAt ?? event.timestamp, event.timestamp)
            }
            let answerConfirmed = confirmsAnswer(event)
            let terminal = [.completed, .failed, .cancelled].contains(classified)
            let state = task.pendingQuestion != nil && !answerConfirmed && !terminal
                ? ActivityState.waitingForInput : classified
            if state != .idle { task.state = state }
            if task.startedAt == nil && state.isActive { task.startedAt = event.timestamp }
            if state.isActive && state != .waitingForInput && state != .attentionRequired {
                if task.activityIntervals.last?.end != nil || task.activityIntervals.isEmpty {
                    task.activityIntervals.append(.init(start: event.timestamp, end: nil))
                }
            } else if [.completed, .failed, .cancelled, .waitingForInput, .attentionRequired].contains(state),
                      let index = task.activityIntervals.indices.last,
                      task.activityIntervals[index].end == nil {
                task.activityIntervals[index].end = event.timestamp
            }
            if state == .completed { task.completedTurns.append(event.timestamp) }
            if let question = Self.extractQuestion(from: event), !answeredQuestionIDs.contains(question.id) {
                task.pendingQuestion = question
                pendingQuestionCallID = event.payload["payload"]?.field("call_id")?.string
                task.state = .waitingForInput
            }
            if answerConfirmed, let question = task.pendingQuestion {
                answeredQuestionIDs.insert(question.id)
                task.pendingQuestion = nil
                pendingQuestionCallID = nil
            }
            if terminal {
                turnEnded = true
                task.pendingQuestion = nil
                pendingQuestionCallID = nil
            }
            if let quota = Self.extractQuota(from: event) {
                if task.quota == nil || quota.windowMinutes > task.quota!.windowMinutes ||
                    (quota.windowMinutes == task.quota!.windowMinutes &&
                     (quota.observedAt ?? .distantPast) >= (task.quota!.observedAt ?? .distantPast)) {
                    task.quota = quota
                }
            }
        }
    }

    mutating func markSubmissionStarted(questionID: String) -> Bool {
        guard !answeredQuestionIDs.contains(questionID) else { return false }
        answeredQuestionIDs.insert(questionID)
        return true
    }

    static func extractQuestion(from event: RolloutEvent) -> PendingQuestion? {
        let toolName = event.payload["payload"]?.field("name")?.string ?? event.payload["name"]?.string
        guard toolName == "request_user_input" || (event.type == "event" && event.text.contains("request_user_input")) else { return nil }
        let root = foundationObject(event.payload)
        func search(_ value: Any) -> [[String: Any]]? {
            if let dictionary = value as? [String: Any] {
                if let questions = dictionary["questions"] as? [[String: Any]] { return questions }
                for child in dictionary.values {
                    if let found = search(child) { return found }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let found = search(child) { return found }
                }
            } else if let string = value as? String,
                      let data = string.data(using: .utf8),
                      let decoded = try? JSONSerialization.jsonObject(with: data) {
                return search(decoded)
            }
            return nil
        }
        guard let question = search(root)?.first else { return nil }
        let prompt = question["question"] as? String ?? question["prompt"] as? String ?? "Codex needs input"
        let id = question["id"] as? String ?? String(prompt.hashValue)
        let options: [QuestionChoice] = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> QuestionChoice? in
            guard let label = option["label"] as? String else { return nil }
            return QuestionChoice(label: label, description: option["description"] as? String ?? "")
        }
        return PendingQuestion(
            id: id,
            header: question["header"] as? String ?? "Input required",
            prompt: prompt,
            choices: options
        )
    }

    static func extractQuota(from event: RolloutEvent) -> QuotaWindow? {
        var candidates: [QuotaWindow] = []
        func resetDate(_ value: JSONValue?) -> Date? {
            switch value {
            case let .number(value) where value.isFinite && value > 0:
                return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1_000 : value)
            case let .string(value):
                if let date = RolloutParser.parseDate(value) { return date }
                if let seconds = Double(value), seconds.isFinite && seconds > 0 {
                    return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1_000 : seconds)
                }
                return nil
            default: return nil
            }
        }
        func walk(_ value: JSONValue, insideLimits: Bool = false) {
            switch value {
            case let .object(object):
                if let limits = object["rate_limits"] ?? object["rateLimits"] {
                    walk(limits, insideLimits: true)
                }
                guard insideLimits else {
                    object.values.forEach { walk($0) }
                    return
                }
                let percent = object["used_percent"]?.number ?? object["percent_used"]?.number
                let utilization = object["utilization"]?.number
                let used = percent ?? utilization.map { $0 <= 1 ? $0 * 100 : $0 }
                let minutes = ["window_minutes", "window_mins", "limit_window_minutes"]
                    .compactMap { object[$0]?.number }.first
                if let used, used.isFinite, (0...100).contains(used),
                   let minutes, minutes.isFinite, minutes > 0, minutes <= 525_600,
                   minutes.rounded() == minutes {
                    candidates.append(.init(
                        usedPercent: used,
                        windowMinutes: Int(minutes),
                        resetAt: resetDate(object["reset_at"] ?? object["resets_at"]),
                        observedAt: event.timestamp
                    ))
                }
                object.values.forEach { walk($0, insideLimits: true) }
            case let .array(array): array.forEach { walk($0, insideLimits: insideLimits) }
            default: break
            }
        }
        walk(.object(event.payload))
        return candidates.max { left, right in
            left.windowMinutes == right.windowMinutes
                ? (left.observedAt ?? .distantPast) < (right.observedAt ?? .distantPast)
                : left.windowMinutes < right.windowMinutes
        }
    }

    private static func foundationObject(_ payload: [String: JSONValue]) -> [String: Any] {
        payload.mapValues(foundation)
    }

    private static func foundation(_ value: JSONValue) -> Any {
        switch value {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case let .object(value): value.mapValues(foundation)
        case let .array(value): value.map(foundation)
        case .null: NSNull()
        }
    }

    private func confirmsAnswer(_ event: RolloutEvent) -> Bool {
        let payload = event.payload["payload"]
        guard event.type == "response_item",
              payload?.field("type")?.string == "function_call_output",
              let pendingQuestionCallID else { return false }
        return payload?.field("call_id")?.string == pendingQuestionCallID
    }
}

enum SnapshotAggregator {
    static func dailyStats(tasks: [TaskSnapshot], now: Date, calendar: Calendar = .current) -> DailyStats {
        let start = calendar.startOfDay(for: now)
        let completed = tasks.flatMap(\.completedTurns).filter { $0 >= start && $0 <= now }.count
        let intervals = tasks.flatMap { task in
            task.activityIntervals.compactMap { interval -> (Date, Date)? in
                let lower = max(interval.start, start)
                let upper = min(interval.end ?? task.updatedAt.addingTimeInterval(120), now)
                return upper > lower ? (lower, upper) : nil
            }
        }.sorted { $0.0 < $1.0 }
        var duration = 0.0
        var current: (Date, Date)?
        for interval in intervals {
            if let existing = current, interval.0 <= existing.1 {
                current = (existing.0, max(existing.1, interval.1))
            } else {
                if let existing = current { duration += existing.1.timeIntervalSince(existing.0) }
                current = interval
            }
        }
        if let current { duration += current.1.timeIntervalSince(current.0) }
        return .init(completedTurns: completed, activeDuration: duration)
    }

    static func quota(tasks: [TaskSnapshot], now: Date = Date()) -> QuotaWindow? {
        tasks.compactMap { task -> (QuotaWindow, Date)? in
            guard let quota = task.quota, quota.isCurrent(at: now) else { return nil }
            return (quota, quota.observedAt ?? task.updatedAt)
        }.max { left, right in
            left.0.windowMinutes == right.0.windowMinutes
                ? left.1 < right.1 : left.0.windowMinutes < right.0.windowMinutes
        }?.0
    }
}
