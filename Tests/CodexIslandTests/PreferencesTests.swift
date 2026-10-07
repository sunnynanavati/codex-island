import Foundation
import XCTest
@testable import CodexIsland

final class PreferencesTests: XCTestCase {
    @MainActor func testDeletingPresetPreservesCurrentSettingsAndOtherPresets() {
        let store = PreferencesStore(defaults: nil)
        store.values.statusGap = 13
        store.savePreset(name: "Quiet")
        store.savePreset(name: "Second")
        let selected = store.presets[0]
        let values = store.values
        // Merely selecting a preset for confirmation must not remove it.
        XCTAssertEqual(store.presets.count, 2)
        store.deletePreset(id: selected.id)
        XCTAssertEqual(store.presets.map(\.name), ["Second"])
        XCTAssertEqual(store.values, values)
        store.deletePreset(id: selected.id)
        XCTAssertEqual(store.presets.count, 1)
    }

    @MainActor func testLegacyPreferencesMigrateOnceWithoutOverwritingNewChoices() throws {
        let suite = "CodexIsland.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        Calibration(horizontalOffset: 22, shoulderReach: 80, waveReach: 150).save(to: defaults)
        CompactTypography(statusSize: 13, statusWeight: .semibold, quotaSize: 9).save(to: defaults)
        defaults.set(false, forKey: "animationsEnabled")
        defaults.set("symbols", forKey: "glyphTheme")
        let store = PreferencesStore(defaults: defaults)
        XCTAssertEqual(store.values.calibration.horizontalOffset, 22)
        XCTAssertEqual(store.values.calibration.waveReach, 150)
        XCTAssertEqual(store.values.typography.statusSize, 13)
        XCTAssertEqual(store.values.glyphTheme, .symbols)
        XCTAssertFalse(store.values.animationsEnabled)
        store.values.typography.statusSize = 11
        CompactTypography(statusSize: 14).save(to: defaults)
        XCTAssertEqual(PreferencesStore(defaults: defaults).values.typography.statusSize, 11)
    }

    @MainActor func testPresetsPreserveVisibilityAndHaveIndependentIdentity() {
        let store = PreferencesStore(defaults: nil)
        store.values.showIsland = false
        store.values.statusGap = 14
        store.values.accent = .purple
        store.savePreset(name: "  Quiet  ")
        let saved = store.presets[0]
        XCTAssertEqual(saved.name, "Quiet")
        store.values.statusGap = 7
        store.applyPreset(saved)
        XCTAssertFalse(store.values.showIsland)
        XCTAssertEqual(store.values.statusGap, 14)
        XCTAssertEqual(store.values.accent, .purple)
        store.duplicatePreset(id: saved.id)
        XCTAssertNotEqual(store.presets[0].id, store.presets[1].id)
        store.renamePreset(id: saved.id, name: "Renamed")
        XCTAssertEqual(store.presets[0].name, "Renamed")
        XCTAssertEqual(store.presets[1].name, "Quiet copy")
        store.deletePreset(id: saved.id)
        XCTAssertEqual(store.presets.count, 1)
        store.resetAll()
        XCTAssertEqual(store.presets.count, 1)
    }

    @MainActor func testPresetPersistenceAndSectionResetIsolation() throws {
        let suite = "CodexIsland.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        store.values.statusGap = 15
        store.values.statusBlur = 1
        store.values.typography.statusSize = 14
        store.savePreset(name: "Custom")
        store.resetAppearance()
        XCTAssertEqual(store.values.typography, CompactTypography())
        XCTAssertEqual(store.values.statusGap, 15)
        XCTAssertEqual(store.values.statusBlur, 1)
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets.first?.values.typography.statusSize, 14)
        XCTAssertEqual(reloaded.values.typography.statusSize, 12)
    }

    @MainActor func testUnsafeSettingsAreClampedAndNonFiniteValuesRecover() {
        var value = IslandPreferences()
        value.typography.statusSize = 999
        value.statusGap = -50
        value.ringStroke = 100
        value.statusDuration = .nan
        value.statusBlur = .infinity
        value.calibration.compactSize = -1
        value.calibration.waveReach = 999
        value.hoverEntryMS = 0
        value.hoverExitMS = 999
        value.springSpeed = 3
        let store = PreferencesStore(defaults: nil, initial: value)
        XCTAssertEqual(store.values.typography.statusSize, 14)
        XCTAssertEqual(store.values.statusGap, 6)
        XCTAssertEqual(store.values.ringStroke, 1.8)
        XCTAssertEqual(store.values.statusDuration, 0.28)
        XCTAssertEqual(store.values.statusBlur, 3)
        XCTAssertEqual(store.values.calibration.compactSize, 0)
        XCTAssertEqual(store.values.calibration.waveReach, 220)
        XCTAssertEqual(store.values.hoverEntryMS, 80)
        XCTAssertEqual(store.values.hoverExitMS, 500)
        XCTAssertEqual(store.values.springSpeed, 1.2)
    }

    @MainActor func testSharedSettingsReachBothModelsAndPreviewDoesNotWriteBack() async {
        let shared = PreferencesStore(defaults: nil)
        let first = AppModel(fixture: IslandFixtures.snapshot("idle"), preferences: shared)
        let second = AppModel(fixture: IslandFixtures.snapshot("active"), preferences: shared)
        var layoutChanges = 0
        first.onLayoutChange = { layoutChanges += 1 }
        shared.values.typography.statusSize = 13.5
        shared.values.calibration.horizontalOffset = 10
        XCTAssertEqual(first.typography.statusSize, 13.5)
        XCTAssertEqual(second.typography.statusSize, 13.5)
        XCTAssertEqual(second.calibration.horizontalOffset, 10)
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertGreaterThan(layoutChanges, 0)
        let preview = PreferencesStore(defaults: nil, initial: shared.values)
        preview.values.typography.statusSize = 10
        XCTAssertEqual(shared.values.typography.statusSize, 13.5)
    }
}
