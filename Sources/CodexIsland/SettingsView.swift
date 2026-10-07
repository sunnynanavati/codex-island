import AppKit
import SwiftUI

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", layout = "Layout", motion = "Motion"
    case presets = "Presets", advanced = "Advanced & About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .layout: "rectangle.topthird.inset.filled"
        case .motion: "waveform.path"
        case .presets: "square.stack"
        case .advanced: "info.circle"
        }
    }
    var hasPreview: Bool { self == .appearance || self == .layout || self == .motion }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    let services: AppServices
    @State private var page: SettingsPage? = .general
    @State private var confirmReset = false

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 185, max: 210)
        } detail: {
            VStack(spacing: 0) {
                if (page ?? .general).hasPreview {
                    SettingsIslandPreview(values: preferences.values)
                    Divider()
                }
                content.formStyle(.grouped)
            }
            .navigationTitle((page ?? .general).rawValue)
        }
        .tint(preferences.values.accent.color)
        .frame(minWidth: 820, minHeight: 620)
        .confirmationDialog("Restore all settings?", isPresented: $confirmReset) {
            Button("Restore Defaults", role: .destructive) { preferences.resetAll() }
        } message: { Text("Your saved presets are kept. Appearance, layout, motion, and island preferences return to their defaults.") }
    }

    @ViewBuilder private var content: some View {
        switch page ?? .general {
        case .general: GeneralSettings(preferences: preferences, services: services)
        case .appearance: appearance
        case .layout: layout
        case .motion: motion
        case .presets: PresetSettings(preferences: preferences)
        case .advanced:
            Form {
                Section("Codex Island") {
                    LabeledContent("Version", value: services.version)
                    Text("A quiet companion for your local Codex chats.").foregroundStyle(.secondary)
                }
                SettingsDiagnostics(model: services.model)
                Section("Privacy & licenses") {
                    Text("Task metadata and rollouts are read locally and never modified. No analytics, telemetry, or account credentials are collected. Codex handles authenticated quota requests.")
                    Text("Codex Island is MIT licensed. Nunito is distributed under the SIL Open Font License. Licenses are included with the app.")
                        .foregroundStyle(.secondary)
                }
                Section("Reset") {
                    Button("Restore All Defaults…") { confirmReset = true }
                    Text("Use the section resets to change only appearance, layout, or motion.").font(.caption).foregroundStyle(.secondary)
                }
                Section { Button("Quit Codex Island") { services.quit() } }
            }
        }
    }

    private var appearance: some View {
        Form {
            Section("Companion") {
                Picker("Style", selection: $preferences.values.glyphTheme) {
                    Text("Cube").tag(IslandGlyphTheme.cube)
                    Text("Semantic symbols").tag(IslandGlyphTheme.symbols)
                }
                Picker("Accent", selection: $preferences.values.accent) {
                    ForEach(IslandAccent.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("The first solved cube stays green. Quota below 25% stays red.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Typography") {
                Picker("Font", selection: $preferences.values.fontFamily) {
                    ForEach(IslandFontFamily.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingSlider("State text size", value: $preferences.values.typography.statusSize,
                              range: CompactTypography.statusSizeRange, step: 0.5, unit: "pt")
                weightPicker("State text weight", selection: $preferences.values.typography.statusWeight)
                SettingSlider("Quota number size", value: $preferences.values.typography.quotaSize,
                              range: CompactTypography.quotaSizeRange, step: 0.5, unit: "pt")
                weightPicker("Quota number weight", selection: $preferences.values.typography.quotaWeight)
            }
            Section { Button("Reset Appearance") { preferences.resetAppearance() } }
        }
    }

    private var layout: some View {
        Form {
            Section("Island") {
                SettingSlider("Horizontal position", value: $preferences.values.calibration.horizontalOffset,
                              range: -120...120, step: 1, unit: "pt")
                SettingSlider("Working island size", value: $preferences.values.calibration.compactSize,
                              range: 0...1, step: 0.01, unit: "", multiplier: 100)
                Text("Idle always fits the cube and quota ring. While working, smallest fits the contents and largest matches the hover tray.").font(.caption).foregroundStyle(.secondary)
                Toggle("Adapt width to content", isOn: $preferences.values.calibration.adaptiveWidth)
                SettingSlider("Width adjustment", value: $preferences.values.calibration.widthAdjustment,
                              range: -120...120, step: 1, unit: "pt")
            }
            Section("Curve & spacing") {
                Toggle("Automatic wave reach", isOn: Binding(
                    get: { preferences.values.calibration.waveReach == nil },
                    set: { preferences.values.calibration.waveReach = $0 ? nil : 140 }))
                SettingSlider("Wave reach", value: Binding(
                    get: { preferences.values.calibration.waveReach ?? 140 },
                    set: { preferences.values.calibration.waveReach = $0 }), range: 40...220, step: 1, unit: "pt")
                    .disabled(preferences.values.calibration.waveReach == nil)
                if preferences.values.calibration.waveReach == nil {
                    Text("Wave reach is fitted automatically to the island contents.").font(.caption).foregroundStyle(.secondary)
                }
                SettingSlider("Drawer shoulder", value: $preferences.values.calibration.shoulderReach,
                              range: 0...140, step: 1, unit: "pt")
                SettingSlider("Text to ring spacing", value: $preferences.values.statusGap,
                              range: 6...16, step: 0.5, unit: "pt")
                SettingSlider("Ring stroke", value: $preferences.values.ringStroke,
                              range: 0.8...1.8, step: 0.1, unit: "pt")
            }
            Section { Button("Reset Layout") { preferences.resetLayout() } }
        }
    }

    private var motion: some View {
        Form {
            Section("Animation") {
                Toggle("Enable animations", isOn: $preferences.values.animationsEnabled)
                Toggle("Animate active cubes", isOn: $preferences.values.cubeAnimationsEnabled)
                    .disabled(!preferences.values.animationsEnabled)
                Text("macOS Reduce Motion replaces movement with fades and static cubes.").font(.caption).foregroundStyle(.secondary)
            }
            Section("State changes") {
                Picker("Transition", selection: $preferences.values.statusTransition) {
                    ForEach(StatusTransitionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingSlider("Duration", value: $preferences.values.statusDuration,
                              range: 0.18...0.30, step: 0.01, unit: "ms", multiplier: 1000)
                SettingSlider("Blur", value: $preferences.values.statusBlur, range: 0...3, step: 0.1, unit: "pt")
            }.disabled(!preferences.values.animationsEnabled)
            Section("Island response") {
                SettingSlider("Spring speed", value: $preferences.values.springSpeed, range: 0.8...1.2, step: 0.05, unit: "×")
                    .disabled(!preferences.values.animationsEnabled)
                SettingSlider("Hover entry", value: $preferences.values.hoverEntryMS, range: 80...400, step: 10, unit: "ms")
                SettingSlider("Hover exit grace", value: $preferences.values.hoverExitMS, range: 100...500, step: 10, unit: "ms")
            }
            Section { Button("Reset Motion") { preferences.resetMotion() } }
        }
    }

    private func weightPicker(_ title: String, selection: Binding<CompactFontWeight>) -> some View {
        Picker(title, selection: selection) {
            ForEach(CompactFontWeight.allCases, id: \.self) { Text($0.title).tag($0) }
        }
    }
}

private struct SettingSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var multiplier = 1.0

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
         unit: String, multiplier: Double = 1) {
        self.title = title; _value = value; self.range = range; self.step = step
        self.unit = unit; self.multiplier = multiplier
    }
    var body: some View {
        LabeledContent(title) {
            Slider(value: $value, in: range, step: step).frame(maxWidth: 190)
                .accessibilityLabel(title)
            Text("\((value * multiplier).formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

@MainActor private struct GeneralSettings: View {
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var services: AppServices
    var body: some View {
        Form {
            Section {
                Text("Your chats, at a glance.").font(.title2.weight(.semibold))
                Text("Codex Island lives at the top of your display. Hover for a preview, click to expand, and press Escape to collapse. Use the menu-bar icon to return to Settings.")
                    .foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Toggle("Show island", isOn: $preferences.values.showIsland)
                Toggle("Preview on hover", isOn: $preferences.values.hoverPreviewEnabled)
                Toggle("Launch at Login", isOn: Binding(get: { services.loginEnabled }, set: { services.setLoginEnabled($0) }))
                if let message = services.loginMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsDiagnostics(model: services.model)
            Section {
                HStack {
                    Button("Open Codex") { services.openCodex() }
                    Button("Refresh") { Task { await services.refresh() } }
                }
            }
        }
    }
}

@MainActor private struct SettingsDiagnostics: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Section("Connection") {
            LabeledContent("Codex application", value: CodexInstallation.applicationURL() == nil ? "Not found — install or open Codex" : "Available")
            LabeledContent("Task source", value: "Local SQLite and rollout files (read-only)")
            if let error = model.snapshot.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Label(model.snapshot.refreshedAt == .distantPast ? "Waiting for local Codex data" : "Reading local Codex data", systemImage: "externaldrive")
            }
            if model.snapshot.refreshedAt != .distantPast {
                LabeledContent("Last task refresh", value: model.snapshot.refreshedAt.formatted(date: .abbreviated, time: .standard))
            }
            LabeledContent("Active chats", value: String(model.snapshot.activeAgentCount))
            if let quota = model.snapshot.quota, let checked = quota.observedAt {
                LabeledContent("Quota checked", value: checked.formatted(date: .abbreviated, time: .standard))
            } else {
                LabeledContent("Quota", value: "Unavailable — awaiting a fresh account report")
            }
            Text("Quota updates are managed separately from task monitoring.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private struct PresetSettings: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var name = ""
    @State private var renaming: UUID?
    @State private var rename = ""
    @State private var deleting: AppearancePreset?
    var body: some View {
        Form {
            Section("Save this look") {
                TextField("Preset name", text: $name)
                Button("Save Current Settings") {
                    preferences.savePreset(name: name.trimmingCharacters(in: .whitespacesAndNewlines)); name = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Presets include appearance, layout, and motion. Startup and account information are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Built-in") {
                LabeledContent("Default") {
                    Button("Apply") { preferences.resetAppearance(); preferences.resetLayout(); preferences.resetMotion() }
                        .accessibilityLabel("Apply Default preset")
                }
            }
            Section("Your presets") {
                if preferences.presets.isEmpty { Text("Save a look to make it easy to return to.").foregroundStyle(.secondary) }
                ForEach(preferences.presets) { preset in
                    LabeledContent(preset.name) {
                        Button("Apply") { preferences.applyPreset(preset) }.accessibilityLabel("Apply \(preset.name)")
                        Menu {
                            Button("Rename…") { rename = preset.name; renaming = preset.id }
                            Button("Duplicate") { preferences.duplicatePreset(id: preset.id) }
                            Button("Delete…", role: .destructive) { deleting = preset }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                            .accessibilityLabel("Actions for \(preset.name)")
                    }
                }
            }
        }
        .alert("Rename Preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $rename)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let id = renaming { preferences.renamePreset(id: id, name: rename) }; renaming = nil
            }.disabled(rename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete preset?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { preset in
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete preset", role: .destructive) {
                preferences.deletePreset(id: preset.id)
                deleting = nil
            }
        } message: { preset in
            Text("Delete “\(preset.name)”? This cannot be undone. Your current settings will not change.")
        }
    }
}
