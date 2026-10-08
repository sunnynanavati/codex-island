import Foundation
import SQLite3

enum CodexDataError: LocalizedError {
    case databaseMissing, noCompatibleTable, database(String)
    var errorDescription: String? {
        switch self {
        case .databaseMissing: "Codex state database was not found. Open Codex once, then refresh."
        case .noCompatibleTable:
            "This Codex task database format is not supported. Check for Codex and Codex Island updates, then reopen Codex and refresh. If this persists, report the compatibility issue; do not delete the database."
        case let .database(message):
            "Could not read Codex tasks. Refresh to retry. If this persists, reopen Codex and refresh again. Details: \(message)"
        }
    }
}

actor CodexDataStore {
    private let codexRoot: URL
    private var tailers: [String: IncrementalJSONLTailer] = [:]
    private var reducers: [String: TaskReducer] = [:]
    private var cachedTasks: [String: TaskSnapshot] = [:]
    private var requestBootstrapAttempts: Set<String> = []
    private var selector = PrimaryTaskSelector()

    init(codexRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexRoot = codexRoot
    }

    func loadSnapshot(now: Date = Date()) throws -> IslandSnapshot {
        let rows = try discoverRows()
        var tasks: [TaskSnapshot] = []
        for row in rows {
            var task = cachedTasks[row.id] ?? TaskSnapshot(
                id: row.id, title: row.title, workspacePath: row.workspace,
                rolloutPath: row.rollout, state: row.state, updatedAt: row.updatedAt,
                startedAt: nil, completedTurns: [], activityIntervals: [], pendingQuestion: nil, quota: nil,
                isChildAgent: row.isChild, agentCount: 1, error: nil
            )
            task.title = row.title
            task.workspacePath = row.workspace ?? task.workspacePath
            task.rolloutPath = row.rollout ?? task.rolloutPath
            task.updatedAt = max(task.updatedAt, row.updatedAt)
            task.isChildAgent = row.isChild
            task.rootChatID = row.rootChatID
            var lastActivityAt: Date?
            if let path = resolveRolloutPath(row: row) {
                do {
                    var tailer = tailers[row.id] ?? IncrementalJSONLTailer()
                    let lines = try tailer.readNewLines(at: URL(fileURLWithPath: path))
                    tailers[row.id] = tailer
                    let events = lines.compactMap(RolloutParser.parse)
                    var reducer = reducers[row.id] ?? TaskReducer()
                    reducer.reduce(task: &task, events: events)
                    if task.latestUserRequest == nil, !task.isChildAgent,
                       task.state.isActive || task.state.needsAttention,
                       requestBootstrapAttempts.insert(row.id).inserted {
                        if let request = try RolloutParser.latestUserRequest(at: URL(fileURLWithPath: path)) {
                            task.latestUserRequest = request.text
                            task.latestUserRequestAt = request.timestamp
                        }
                    }
                    lastActivityAt = reducer.lastActivityAt
                    reducers[row.id] = reducer
                } catch {
                    task.error = "Rollout temporarily unavailable"
                }
            }
            // A long thinking step can be quiet. Give it room, but do not show
            // an abandoned turn as active indefinitely when no terminal event arrives.
            if task.state.isActive && task.pendingQuestion == nil,
               now.timeIntervalSince(lastActivityAt ?? task.updatedAt) > 30 * 60 {
                task.state = .idle
            }
            cachedTasks[row.id] = task
            tasks.append(task)
        }
        tasks.sort { $0.updatedAt > $1.updatedAt }
        let primary = selector.select(from: tasks, now: now)
        return IslandSnapshot(
            tasks: tasks,
            primaryTaskID: primary,
            dailyStats: SnapshotAggregator.dailyStats(tasks: tasks, now: now),
            quota: SnapshotAggregator.quota(tasks: tasks, now: now),
            refreshedAt: now,
            errorMessage: nil
        )
    }

    private struct Row {
        var id: String
        var title: String
        var workspace: String?
        var rollout: String?
        var updatedAt: Date
        var state: ActivityState
        var isChild: Bool
        var sourceParentID: String?
        var rootChatID: String?
    }

    private func discoverRows() throws -> [Row] {
        let path = codexRoot.appendingPathComponent("state_5.sqlite").path
        guard FileManager.default.fileExists(atPath: path) else { throw CodexDataError.databaseMissing }
        var database: OpaquePointer?
        let uri = "file:\(path)?mode=ro"
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            throw CodexDataError.database("SQLite open failed")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1000)
        let tables = try query(database, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .compactMap { $0["name"] }
        let candidates = try tables.map { table -> (String, Set<String>, Int) in
            let columns = Set(
                try query(database, sql: "PRAGMA table_info(\"\(escaped(table))\")").compactMap { $0["name"] }
            )
            var score = table.lowercased().contains("thread") ? 10 : 0
            if columns.contains("rollout_path") { score += 10 }
            if columns.contains("cwd") || columns.contains("workspace_path") { score += 4 }
            if columns.contains("title") || columns.contains("first_user_message") { score += 4 }
            if columns.contains("updated_at") || columns.contains("updated_at_ms") { score += 2 }
            return (table, columns, score)
        }.sorted { $0.2 > $1.2 }
        for (table, columns, _) in candidates {
            guard columns.contains("id") || columns.contains("thread_id") else { continue }
            guard columns.contains("title") || columns.contains("name") || columns.contains("cwd") else { continue }
            let orderColumn = columns.contains("updated_at_ms") ? "updated_at_ms" :
                columns.contains("updated_at") ? "updated_at" : "rowid"
            let rows = try query(
                database,
                sql: "SELECT * FROM \"\(escaped(table))\" ORDER BY \"\(orderColumn)\" DESC LIMIT 80"
            )
            if !rows.isEmpty {
                var parsed = rows.compactMap(row(from:))
                var parents = try spawnParents(database: database, tables: candidates)
                for row in parsed {
                    if let parent = row.sourceParentID, parents[row.id] == nil {
                        parents[row.id] = parent
                    }
                }
                for index in parsed.indices where parsed[index].isChild {
                    parsed[index].rootChatID = ThreadLineage.rootID(for: parsed[index].id, parents: parents)
                }
                return parsed
            }
            return []
        }
        throw CodexDataError.noCompatibleTable
    }

    private func row(from values: [String: String]) -> Row? {
        guard let id = pick(values, ["id", "thread_id", "session_id"]) else { return nil }
        let title = pick(values, ["title", "name", "prompt", "task"]) ?? "Codex task"
        let workspace = pick(values, ["cwd", "workspace_path", "path", "working_directory"])
        let rollout = pick(values, ["rollout_path", "rollout_file", "jsonl_path"])
        let updatedText = pick(values, ["updated_at", "last_updated_at", "created_at", "timestamp"])
        let date = parseDate(updatedText) ?? Date.distantPast
        let status = pick(values, ["status", "state"])?.lowercased() ?? ""
        let state: ActivityState = status.contains("complete") ? .completed :
            status.contains("fail") ? .failed :
            status.contains("cancel") ? .cancelled : .idle
        let source = pick(values, ["thread_source", "source", "origin", "kind"]) ?? ""
        let agentRole = pick(values, ["agent_role"])?.lowercased() ?? ""
        return Row(id: id, title: title, workspace: workspace, rollout: rollout,
                   updatedAt: date, state: state,
                   isChild: source.lowercased().contains("subagent") || source.lowercased().contains("child") ||
                       (!agentRole.isEmpty && agentRole != "user" && agentRole != "default"),
                   sourceParentID: ThreadLineage.parentID(in: source), rootChatID: nil)
    }

    private func spawnParents(database: OpaquePointer, tables: [(String, Set<String>, Int)]) throws -> [String: String] {
        var parents: [String: String] = [:]
        for (table, columns, _) in tables where columns.contains("parent_thread_id") && columns.contains("child_thread_id") {
            let rows = try query(database, sql: "SELECT parent_thread_id, child_thread_id FROM \"\(escaped(table))\"")
            for row in rows {
                if let child = row["child_thread_id"], let parent = row["parent_thread_id"],
                   !child.isEmpty, !parent.isEmpty {
                    parents[child] = parent
                }
            }
        }
        return parents
    }

    private func resolveRolloutPath(row: Row) -> String? {
        if let path = row.rollout, FileManager.default.fileExists(atPath: path) { return path }
        let sessions = codexRoot.appendingPathComponent("sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl", url.lastPathComponent.contains(row.id) { return url.path }
        }
        return nil
    }

    private func query(_ database: OpaquePointer, sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw CodexDataError.database(String(cString: sqlite3_errmsg(database))) }
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, index) else { continue }
                let key = String(cString: name)
                if let text = sqlite3_column_text(statement, index) {
                    row[key] = String(cString: text)
                }
            }
            result.append(row)
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw CodexDataError.database(String(cString: sqlite3_errmsg(database))) }
        return result
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }
    private func pick(_ row: [String: String], _ keys: [String]) -> String? {
        keys.compactMap { row[$0] }.first
    }
    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
        }
        return RolloutParser.parseDate(value)
    }
}
