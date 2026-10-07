import AppKit
import SwiftUI

@MainActor
struct SettingsIslandPreview: View {
    let values: IslandPreferences
    @State private var scenario = "active"
    @State private var stage = 0
    @State private var replay = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Live preview").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Scenario", selection: $scenario) {
                    Text("Idle").tag("idle")
                    Text("Active").tag("active")
                    Text("Multiple chats").tag("multiple")
                    Text("Mixed completion").tag("mixed")
                    Text("Attention").tag("attention")
                    Text("Completed").tag("completed")
                    Text("Failed").tag("failed")
                    Text("Quota unavailable").tag("unavailable")
                }.frame(width: 190)
            }
            Picker("Presentation", selection: $stage) {
                Text("Compact").tag(0)
                Text("Hover").tag(1)
                Text("Expanded").tag(2)
            }.pickerStyle(.segmented).frame(maxWidth: 340)
            if scenario == "completed" {
                Button("Replay completion") { replay += 1 }.font(.caption)
            }
            PreviewSurface(values: values, scenario: scenario, stage: stage, replay: replay)
                .frame(height: 205)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Synthetic island preview")
            Text("Sample chats only. Changes also apply to your island.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }
}

@MainActor private struct PreviewSurface: NSViewRepresentable {
    let values: IslandPreferences
    let scenario: String
    let stage: Int
    let replay: Int
    func makeNSView(context: Context) -> PreviewHost { PreviewHost(values: values) }
    func updateNSView(_ view: PreviewHost, context: Context) {
        view.update(values: values, scenario: scenario, stage: stage, replay: replay)
    }
    static func dismantleNSView(_ view: PreviewHost, coordinator: ()) { view.stop() }
}

@MainActor private final class PreviewHost: NSView {
    private let preferences: PreferencesStore
    private let model: AppModel
    private let motion: IslandMotionCoordinator
    private var hosting: NSHostingView<PreviewDrawing>!
    private var currentValues: IslandPreferences
    private var scenario = ""
    private var stage = 0
    private var replay = -1
    private var observer: NSObjectProtocol?

    init(values: IslandPreferences) {
        currentValues = values
        preferences = PreferencesStore(defaults: nil, initial: values)
        model = AppModel(fixture: IslandFixtures.snapshot("active"), preferences: preferences)
        let layout = PanelController.layout(calibration: values.calibration, cubeCount: model.cubes.count,
                                            statusLabel: model.compactLabel, typography: values.typography,
                                            preferences: values, sizingLabel: model.rail.sizingLabel,
                                            usesWorkingWidth: model.rail.usesWorkingWidth, expandedBodyHeight: model.expandedBodyHeight)
        motion = IslandMotionCoordinator(layout: layout)
        super.init(frame: .zero)
        hosting = NSHostingView(rootView: PreviewDrawing(model: model, motion: motion))
        hosting.sizingOptions = []
        addSubview(hosting)
        motion.attach(to: hosting)
        model.onLayoutChange = { [weak self] in self?.sync() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() { super.layout(); hosting.frame = bounds }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let window {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                              object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            }
            sync()
        } else { stop() }
    }

    func update(values: IslandPreferences, scenario: String, stage: Int, replay: Int) {
        currentValues = values
        if self.scenario != scenario || self.replay != replay {
            self.scenario = scenario
            self.replay = replay
            if scenario == "completed" || scenario == "mixed" {
                model.setFixture(IslandFixtures.snapshot(scenario == "mixed" ? "multiple" : "active"))
            }
            model.setFixture(IslandFixtures.snapshot(scenario))
        }
        self.stage = stage
        sync()
    }

    private func sync() {
        let visible = window?.occlusionState.contains(.visible) == true
        var values = currentValues
        values.showIsland = true
        if !visible { values.animationsEnabled = false; values.cubeAnimationsEnabled = false }
        if preferences.values != values { preferences.values = values }
        let state: PresentationState = stage == 0 ? .compact : stage == 1 ? .preview : .pinned
        model.presentation = state
        let layout = PanelController.layout(calibration: values.calibration, cubeCount: model.cubes.count,
                                            statusLabel: model.compactLabel, typography: values.typography,
                                            preferences: values, sizingLabel: model.rail.sizingLabel,
                                            usesWorkingWidth: model.rail.usesWorkingWidth, expandedBodyHeight: model.expandedBodyHeight)
        model.notchGap = layout.notchGapWidth
        motion.speed = values.springSpeed
        motion.update(layout: layout, state: state,
                      policy: .resolve(enabled: visible && values.animationsEnabled,
                                       reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        if !visible { motion.stop() }
    }

    func stop() {
        motion.stop()
        model.onLayoutChange = nil
        var values = currentValues
        values.animationsEnabled = false
        values.cubeAnimationsEnabled = false
        preferences.values = values
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
}

private struct PreviewDrawing: View {
    @ObservedObject var model: AppModel
    @ObservedObject var motion: IslandMotionCoordinator
    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, min((geometry.size.width - 24) / motion.frame.width,
                                   (geometry.size.height - 12) / motion.frame.height))
            IslandView(model: model, motion: motion, cubeFrozenOverride: false)
                .frame(width: motion.frame.width, height: motion.frame.height)
                .scaleEffect(scale, anchor: .top)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
