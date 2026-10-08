import Foundation

enum ActivityState: String, Codable, CaseIterable, Sendable {
    case starting, planning, thinking, reading, scanning, searching, editing
    case running, waitingForInput, writing, completed, failed, cancelled
    case attentionRequired, idle

    var label: String {
        switch self {
        case .waitingForInput: "Waiting for input"
        case .attentionRequired: "Attention required"
        case .running: "Running tools"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var isActive: Bool {
        ![.completed, .failed, .cancelled, .idle].contains(self)
    }

    var needsAttention: Bool {
        self == .waitingForInput || self == .attentionRequired || self == .failed
    }
}

struct QuestionChoice: Codable, Equatable, Sendable, Identifiable {
    let label: String
    let description: String
    var id: String { label }
}

struct PendingQuestion: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let header: String
    let prompt: String
    let choices: [QuestionChoice]
}

struct QuotaWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetAt: Date?
    let observedAt: Date?

    init(usedPercent: Double, windowMinutes: Int, resetAt: Date?, observedAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetAt = resetAt
        self.observedAt = observedAt
    }

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    func isCurrent(at now: Date) -> Bool {
        if let resetAt, resetAt <= now { return false }
        guard let observedAt else { return true }
        let age = now.timeIntervalSince(observedAt)
        return age >= -120 && age <= min(TimeInterval(windowMinutes) * 60, 86_400)
    }
}

enum QuotaSeverity: Equatable {
    case unavailable, normal, warning, critical

    init(quota: QuotaWindow?) {
        guard let quota, quota.usedPercent.isFinite else {
            self = .unavailable
            return
        }
        switch quota.remainingPercent {
        case ..<25: self = .critical
        case ..<40: self = .warning
        default: self = .normal
        }
    }
}

struct ActivityInterval: Codable, Equatable, Sendable {
    var start: Date
    var end: Date?
}

struct TaskSnapshot: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var workspacePath: String?
    var rolloutPath: String?
    var state: ActivityState
    var updatedAt: Date
    var startedAt: Date?
    var completedTurns: [Date]
    var activityIntervals: [ActivityInterval]
    var pendingQuestion: PendingQuestion?
    var quota: QuotaWindow?
    var isChildAgent: Bool
    var agentCount: Int
    var error: String?
    var rootChatID: String? = nil
    var latestUserRequest: String? = nil
    var latestUserRequestAt: Date? = nil

    var currentRequestTitle: String {
        Self.cleanTitle(latestUserRequest ?? title)
    }

    var workspaceName: String {
        guard let workspacePath else { return "Unknown workspace" }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }

    var cleanedTitle: String {
        Self.cleanTitle(title)
    }

    private static func cleanTitle(_ text: String) -> String {
        let withoutFence = text.replacingOccurrences(
            of: #"^\s*```[a-zA-Z]*\s*"#, with: "", options: .regularExpression
        ).replacingOccurrences(of: #"\s*```\s*$"#, with: "", options: .regularExpression)
        let line = withoutFence.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "Untitled Codex task" : line
    }
}

struct DailyStats: Equatable, Sendable {
    var completedTurns: Int
    var activeDuration: TimeInterval
}

struct IslandSnapshot: Equatable, Sendable {
    var tasks: [TaskSnapshot]
    var primaryTaskID: String?
    var dailyStats: DailyStats
    var quota: QuotaWindow?
    var refreshedAt: Date
    var errorMessage: String?

    static let empty = IslandSnapshot(
        tasks: [], primaryTaskID: nil,
        dailyStats: .init(completedTurns: 0, activeDuration: 0),
        quota: nil, refreshedAt: .distantPast, errorMessage: nil
    )

    var primaryTask: TaskSnapshot? {
        primaryTaskID.flatMap { id in tasks.first(where: { $0.id == id }) }
    }
    var activeTasks: [TaskSnapshot] { tasks.filter { $0.state.isActive } }
    var recentTasks: [TaskSnapshot] {
        tasks.filter { !$0.state.isActive && !$0.isChildAgent }.prefix(12).map { $0 }
    }
    var attentionCount: Int { tasks.filter { $0.state.needsAttention }.count }
    var activeChatCount: Int {
        let ids = activeTasks.compactMap { task -> String? in
            guard task.isChildAgent else { return task.id }
            guard let root = task.rootChatID, root != task.id else { return nil }
            return root
        }
        return Set(ids).count
    }
    var activeChatSummary: String {
        "\(activeChatCount) active \(activeChatCount == 1 ? "chat" : "chats")"
    }
    var activeAgentCount: Int {
        activeTasks.reduce(0) { $0 + max(1, $1.agentCount) }
    }
}

struct RolloutEvent: Equatable, Sendable {
    let timestamp: Date
    let type: String
    let text: String
    let payload: [String: JSONValue]
}

enum JSONValue: Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue])
    case array([JSONValue]), null

    init(_ value: Any) {
        switch value {
        case let value as String: self = .string(value)
        case let value as NSNumber: self = .number(value.doubleValue)
        case let value as [String: Any]: self = .object(value.mapValues(JSONValue.init))
        case let value as [Any]: self = .array(value.map(JSONValue.init))
        default: self = .null
        }
    }

    var string: String? {
        if case let .string(value) = self { value } else { nil }
    }
    var number: Double? {
        if case let .number(value) = self { value } else { nil }
    }
    func field(_ key: String) -> JSONValue? {
        if case let .object(value) = self { value[key] } else { nil }
    }
}
