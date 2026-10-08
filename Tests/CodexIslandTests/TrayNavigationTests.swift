import XCTest
@testable import CodexIsland

final class TrayNavigationTests: XCTestCase {
    func testFullCleanTitleIsPreservedForTooltip() throws {
        var task = try XCTUnwrap(IslandFixtures.snapshot("active").tasks.first)
        let title = String(repeating: "A detailed task title ", count: 20).trimmingCharacters(in: .whitespaces)
        task.title = "```text\n\(title)\n```"
        XCTAssertEqual(task.cleanedTitle, title)
        XCTAssertGreaterThan(task.cleanedTitle.count, 100)
    }

    @MainActor func testRecentNavigationKeepsTaskIdentityAndPinnedPresentation() throws {
        let model = AppModel(fixture: IslandFixtures.snapshot("active"), preferences: PreferencesStore(defaults: nil))
        let id = try XCTUnwrap(model.snapshot.primaryTaskID)
        model.presentation = .pinned
        model.page = .recent
        XCTAssertEqual(model.page, .recent)
        XCTAssertEqual(model.presentation, .pinned)
        XCTAssertEqual(model.snapshot.primaryTaskID, id)
        model.page = .activity
        XCTAssertEqual(model.page, .activity)
    }
}
