import Foundation
import Darwin

struct QuotaCache: Sendable {
    var value: QuotaWindow?
    var nextCheck = Date.distantPast
    mutating func beginCheck(now: Date) -> Bool {
        guard now >= nextCheck else { return false }
        nextCheck = now.addingTimeInterval(300)
        return true
    }
    func current(now: Date) -> QuotaWindow? {
        guard let value, let observed = value.observedAt,
              (0..<600).contains(now.timeIntervalSince(observed)), value.isCurrent(at: now) else { return nil }
        return value
    }
}

enum AccountQuotaParser {
    static func parse(_ result: [String: Any], now: Date) -> QuotaWindow? {
        // Other model-specific buckets are not the account's core Codex allowance.
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let core: [String: Any]?
        if let buckets { core = buckets["codex"] as? [String: Any] }
        else { core = result["rateLimits"] as? [String: Any] }
        guard let core else { return nil }
        if let limitID = core["limitId"] as? String, limitID != "codex" { return nil }
        return ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard let window = core[key] as? [String: Any],
                  let used = window["usedPercent"] as? Double, used.isFinite, (0...100).contains(used),
                  let minutes = window["windowDurationMins"] as? Int, minutes > 0 else { return nil }
            let reset = (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
            let quota = QuotaWindow(usedPercent: used, windowMinutes: minutes, resetAt: reset, observedAt: now)
            return quota.isCurrent(at: now) ? quota : nil
        }.max { $0.windowMinutes < $1.windowMinutes }
    }
}

// A persistent stdio connection to Codex's own authenticated backend. Only initialize
// and account/rateLimits/read are sent; no task, filesystem or approval requests.
actor LiveQuota {
    func shutdown() { disconnect() }
    private var cache = QuotaCache()
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var requestID = 0

    func quota(now: Date = Date()) async -> QuotaWindow? {
        if process?.isRunning == true { _ = try? receive() }
        guard cache.beginCheck(now: now) else { return cache.current(now: now) }
        do {
            try await connect()
            let result = try await request(method: "account/rateLimits/read", params: nil)
            cache.value = AccountQuotaParser.parse(result, now: Date())
            if let reset = cache.value?.resetAt, reset < cache.nextCheck {
                cache.nextCheck = reset.addingTimeInterval(1)
            }
        } catch {
            disconnect()
        }
        return cache.current(now: Date())
    }

    private func connect() async throws {
        if process?.isRunning == true { return }
        disconnect()
        let candidates = await CodexInstallation.executableCandidates()
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw Failure.unavailable }
        let backend = Process(), stdin = Pipe(), stdout = Pipe()
        backend.executableURL = URL(fileURLWithPath: path)
        backend.arguments = ["app-server"]
        backend.standardInput = stdin
        backend.standardOutput = stdout
        backend.standardError = FileHandle.nullDevice
        try backend.run()
        process = backend; input = stdin; output = stdout
        let fd = stdout.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = try await request(method: "initialize", params: ["clientInfo": ["name": "codex_island", "version": "0.1.0"], "capabilities": [:]])
        try send(["method": "initialized"])
    }

    private func request(method: String, params: [String: Any]?) async throws -> [String: Any] {
        requestID += 1
        let id = requestID
        var message: [String: Any] = ["id": id, "method": method]
        if let params { message["params"] = params }
        try send(message)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            try Task.checkCancellation()
            guard process?.isRunning == true, let output else { throw Failure.unavailable }
            _ = output
            for response in try receive() {
                if response["id"] as? Int == id {
                    guard response["error"] == nil, let result = response["result"] as? [String: Any] else { throw Failure.unavailable }
                    return result
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw Failure.unavailable
    }

    private func receive() throws -> [[String: Any]] {
        guard let output else { return [] }
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
        if count > 0 { buffer.append(contentsOf: bytes.prefix(count)) }
        if count == 0 { throw Failure.unavailable }
        guard buffer.count < 1_048_576 else { throw Failure.unavailable }
        var messages: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if response["method"] as? String == "account/rateLimits/updated",
               let params = response["params"] as? [String: Any],
               let value = AccountQuotaParser.parse(["rateLimits": params["rateLimits"] ?? params], now: Date()) { cache.value = value }
            messages.append(response)
        }
        return messages
    }

    private func send(_ object: [String: Any]) throws {
        guard let input else { throw Failure.unavailable }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func disconnect() {
        try? input?.fileHandleForWriting.close()
        if process?.isRunning == true { process?.terminate() }
        try? output?.fileHandleForReading.close()
        process = nil; input = nil; output = nil; buffer.removeAll()
    }
    private enum Failure: Error { case unavailable }
}
