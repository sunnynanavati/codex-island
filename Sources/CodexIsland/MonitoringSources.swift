import Foundation

protocol TaskSnapshotSource: Sendable {
    func loadSnapshot(now: Date) async throws -> IslandSnapshot
}

protocol QuotaSource: Sendable {
    func quota(now: Date) async -> QuotaWindow?
    func shutdown() async
}

extension CodexDataStore: TaskSnapshotSource {}
extension LiveQuota: QuotaSource {}
