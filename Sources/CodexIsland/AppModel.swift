import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
enum AppLog {
    static func write(_ message: String) {
        guard let data = "[CodexIsland] \(message)\n".data(using: .utf8) else { return }
        try? FileHandle.standardError.write(contentsOf: data)
        if Bundle.main.bundleIdentifier == "com.codexisland.app" || Bundle.main.bundleIdentifier == "com.codexisland.dev" {
            let url = URL(fileURLWithPath: "/tmp/codex-island.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data); try? handle.close()
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = IslandSnapshot.empty
    @Published var presentation = PresentationState.compact
    @Published var page = IslandPage.activity {
        didSet { if page != oldValue { onLayoutChange?() } }
    }
    @Published private(set) var rail = RailPresentation()
    var cubes: [CubeDescriptor] { rail.cubes }
    @Published var notchGap: CGFloat = 180
    let preferences: PreferencesStore
    var calibration: Calibration {
        get { preferences.values.calibration }
        set { preferences.values.calibration = newValue }
    }
    var animationsEnabled: Bool {
        get { preferences.values.animationsEnabled }
        set { preferences.values.animationsEnabled = newValue }
    }
    var glyphTheme: IslandGlyphTheme {
        get { preferences.values.glyphTheme }
        set { preferences.values.glyphTheme = newValue }
    }
    var typography: CompactTypography {
        get { preferences.values.typography }
        set { preferences.values.typography = newValue }
    }
    private var preferenceSubscription: AnyCancellable?

    private let store: any TaskSnapshotSource
    private let liveQuota: any QuotaSource
    private var keeper = SnapshotKeeper()
    private var monitorTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var refreshInProgress = false
    private var hoverExitTask: Task<Void, Never>?
    private var hoverEnterTask: Task<Void, Never>?
    private var pointerInside = false
    private var hoverSuppressed = false
    private var completionTask: Task<Void, Never>?
    let isFixture: Bool
    private var loggedFirstRefresh = false
    private var lastReadError: String?
    private var loggedFirstQuota = false
    var onLayoutChange: (() -> Void)?
    private var lastExpandedBodyHeight: CGFloat?
    var expandedBodyHeight: CGFloat {
        page == .activity && snapshot.primaryTask == nil && snapshot.errorMessage == nil &&
            !snapshot.tasks.contains(where: { $0.state.isActive || $0.state.needsAttention }) ? 222 : 398
    }
    var compactLabel: String {
        rail.label ?? ""
    }

    init(store: any TaskSnapshotSource = CodexDataStore(), quotaSource: any QuotaSource = LiveQuota(), fixture: IslandSnapshot? = nil,
         preferences: PreferencesStore? = nil) {
        self.store = store
        self.liveQuota = quotaSource
        isFixture = fixture != nil
        self.preferences = preferences ?? PreferencesStore(defaults: fixture == nil ? PreferencesStore.appDefaults : nil)
        preferenceSubscription = self.preferences.$values.dropFirst().sink { [weak self] _ in
            // Published sends before storage changes; coalesce onto the next main turn.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.updateRail(now: self.isFixture ? self.snapshot.refreshedAt : Date())
                if !self.preferences.values.hoverPreviewEnabled && self.presentation == .preview { self.dismiss() }
                self.onLayoutChange?()
            }
        }
        if let fixture {
            snapshot = fixture
            rail.update(snapshot: fixture, now: fixture.refreshedAt)
        }
    }

    func start() {
        guard monitorTask == nil, !isFixture else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        quotaTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshQuota()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() async {
        monitorTask?.cancel(); monitorTask = nil
        quotaTask?.cancel(); quotaTask = nil
        hoverEnterTask?.cancel(); hoverExitTask?.cancel()
        completionTask?.cancel(); completionTask = nil
        await liveQuota.shutdown()
    }

    func setFixture(_ value: IslandSnapshot) {
        guard isFixture else { return }
        snapshot = value
        updateRail(now: value.refreshedAt)
        onLayoutChange?()
    }

    func refresh() async {
        guard !isFixture, !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        do {
            let value = try await store.loadSnapshot(now: Date())
            keeper.accept(.success(value))
            lastReadError = nil
            if !loggedFirstRefresh {
                loggedFirstRefresh = true
                AppLog.write(
                    "First refresh succeeded: \(value.tasks.count) tasks, " +
                    "\(value.activeAgentCount) active agents, \(value.attentionCount) attention"
                )
            }
        } catch {
            keeper.accept(.failure(error))
            if lastReadError != error.localizedDescription {
                lastReadError = error.localizedDescription
                AppLog.write("Refresh warning: \(error.localizedDescription)")
            }
        }
        guard !Task.isCancelled else { return }
        let quota = snapshot.quota
        snapshot = keeper.snapshot
        snapshot.quota = quota
        updateRail(now: Date())
    }

    private func updateRail(now: Date) {
        let previous = rail
        rail.update(snapshot: snapshot, now: now,
                    completionAnimated: animationsEnabled && preferences.values.cubeAnimationsEnabled &&
                        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let heightChanged = lastExpandedBodyHeight != expandedBodyHeight
        lastExpandedBodyHeight = expandedBodyHeight
        if rail != previous || heightChanged { onLayoutChange?() }
        guard rail.completionDeadline != previous.completionDeadline else { return }
        completionTask?.cancel()
        completionTask = nil
        guard let deadline = rail.completionDeadline else { return }
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSince(now))))
            guard !Task.isCancelled, let self, self.rail.completionDeadline == deadline else { return }
            self.rail.settle(at: deadline)
            self.completionTask = nil
            self.onLayoutChange?()
        }
    }

    private func refreshQuota() async {
        let value = await liveQuota.quota(now: Date())
        guard !Task.isCancelled else { return }
        snapshot.quota = value
        if let quota = snapshot.quota, !loggedFirstQuota {
            loggedFirstQuota = true
            AppLog.write("Live account quota: \(quota.remainingPercent)% remaining (checks at most every 5 minutes)")
        }
    }

    func hover(_ inside: Bool) {
        guard preferences.values.hoverPreviewEnabled, preferences.values.showIsland else { return }
        if !inside { hoverSuppressed = false }
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            guard !hoverSuppressed, presentation == .compact else { return }
            hoverEnterTask?.cancel()
            hoverEnterTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(self?.preferences.values.hoverEntryMS ?? 120))
                guard !Task.isCancelled, let self, self.pointerInside, !self.hoverSuppressed else { return }
                self.updatePresentation { $0.hover(true) }
            }
        } else {
            hoverEnterTask?.cancel()
            guard presentation == .preview else { return }
            hoverExitTask?.cancel()
            hoverExitTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(self?.preferences.values.hoverExitMS ?? 220))
                guard !Task.isCancelled, let self, self.presentation == .preview else { return }
                self.updatePresentation { $0.hover(false) }
                self.hoverExitTask = nil
            }
        }
    }

    func clickIsland() {
        hoverEnterTask?.cancel()
        hoverExitTask?.cancel()
        hoverExitTask = nil
        updatePresentation { $0.click() }
    }

    func dismiss() {
        hoverEnterTask?.cancel()
        hoverSuppressed = true
        hoverExitTask?.cancel()
        hoverExitTask = nil
        updatePresentation { $0.dismiss() }
        page = .activity
    }

    func resetCalibration() {
        calibration = .init()
        onLayoutChange?()
    }

    func resetTypography() {
        typography = .init()
    }

    func resetShape() {
        calibration.waveReach = nil
        calibration.compactSize = 0
        calibration.adaptiveWidth = true
        onLayoutChange?()
    }

    private func updatePresentation(_ change: (inout PresentationState) -> Void) {
        let previous = presentation
        change(&presentation)
        if presentation != previous { onLayoutChange?() }
    }

    func openCodex(taskID: String? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if let url = CodexInstallation.applicationURL() {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
