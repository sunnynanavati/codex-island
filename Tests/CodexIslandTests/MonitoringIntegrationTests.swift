import XCTest
@testable import CodexIsland

private actor SyntheticTasks: TaskSnapshotSource {
    var reads = 0
    func loadSnapshot(now: Date) async throws -> IslandSnapshot {
        reads += 1
        return IslandSnapshot.empty
    }
}

private actor SlowQuota: QuotaSource {
    var reads = 0
    var stopped = false
    func quota(now: Date) async -> QuotaWindow? {
        reads += 1
        try? await Task.sleep(for: .seconds(60))
        return nil
    }
    func shutdown() { stopped = true }
}

final class MonitoringIntegrationTests: XCTestCase {
    @MainActor func testSlowQuotaDoesNotBlockTaskRefreshAndStopClosesBackend() async throws {
        let tasks = SyntheticTasks()
        let quota = SlowQuota()
        let model = AppModel(store: tasks, quotaSource: quota, preferences: PreferencesStore(defaults: nil))
        model.start()
        model.start()
        try await Task.sleep(for: .milliseconds(100))
        await model.refresh()
        let reads = await tasks.reads
        let quotaReads = await quota.reads
        XCTAssertGreaterThanOrEqual(reads, 2)
        XCTAssertEqual(quotaReads, 1, "Repeated start must not duplicate sessions")
        await model.stop()
        let stopped = await quota.stopped
        XCTAssertTrue(stopped)
    }

    @MainActor func testSyntheticPreviewNeverStartsSources() async throws {
        let tasks = SyntheticTasks()
        let quota = SlowQuota()
        let model = AppModel(store: tasks, quotaSource: quota, fixture: .empty)
        model.start()
        await model.refresh()
        let reads = await tasks.reads
        let quotaReads = await quota.reads
        XCTAssertEqual(reads, 0)
        XCTAssertEqual(quotaReads, 0)
    }
}
