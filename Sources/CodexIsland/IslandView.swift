import SwiftUI

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var motion: IslandMotionCoordinator
    var reduceMotionOverride: Bool? = nil
    var increasedContrastOverride: Bool? = nil
    var cubeFrozenOverride: Bool? = nil
    var nativeSurface = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var increasedContrast: Bool { increasedContrastOverride ?? (systemContrast == .increased) }

    private var rule: Color { .white.opacity(increasedContrast ? 0.45 : 0.12) }
    private var labelAnimation: Animation? {
        model.animationsEnabled ? .easeOut(duration: IslandDesign.labelDuration) : nil
    }
    private var primary: TaskSnapshot? { model.snapshot.primaryTask }
    private var topHeight: CGFloat { motion.layout.compactFrame.height }
    private var bodyWidth: CGFloat { motion.layout.bodyWidth(at: motion.progress) }
    private var islandShape: IslandShape {
        IslandShape(radius: motion.cornerRadius, shoulderReach: motion.layout.shoulderReach(at: motion.progress),
                    shoulderHeight: motion.shoulderHeight,
                    shoulderBlend: min(1, max(0, motion.progress)))
    }
    private var compactLabel: String { model.compactLabel }
    private func statusColor(_ state: ActivityState) -> Color {
        state.isActive && !state.needsAttention ? model.preferences.values.accent.color : IslandDesign.color(state)
    }
    private var previewOpacity: Double {
        IslandContentReveal.previewOpacity(motion.progress, eligible: motion.previewContentEligible)
    }
    private var expandedOpacity: Double {
        IslandContentReveal.expandedOpacity(motion.progress,
                                            previewEligible: motion.previewContentEligible)
    }
    private var expandedInteractive: Bool {
        model.presentation == .pinned && expandedOpacity >= 0.95
    }

    var body: some View {
        VStack(spacing: 0) {
            statusRail
                .frame(width: bodyWidth, height: topHeight)
                .frame(width: motion.frame.width)
                .opacity(motion.contentOpacity)
            ZStack(alignment: .top) {
                preview
                    .frame(width: motion.layout.previewFrame.width - 2 * motion.layout.shoulderReach,
                           height: 116, alignment: .top)
                    .offset(y: IslandContentReveal.previewYOffset(motion.progress, opacity: previewOpacity,
                                                                   movementAllowed: model.animationsEnabled && !reduceMotion))
                    .opacity(previewOpacity)
                    .allowsHitTesting(model.presentation == .preview)
                    .accessibilityHidden(model.presentation != .preview || previewOpacity < 0.95)
                    .disabled(model.presentation != .preview)
                expanded
                    .frame(width: motion.layout.expandedFrame.width - 2 * motion.layout.shoulderReach,
                           height: motion.layout.expandedFrame.height - topHeight)
                    .offset(y: IslandContentReveal.expandedYOffset(opacity: expandedOpacity,
                                                                    movementAllowed: model.animationsEnabled && !reduceMotion))
                    .opacity(expandedOpacity)
                    .allowsHitTesting(expandedInteractive)
                    .accessibilityHidden(!expandedInteractive)
                    .disabled(!expandedInteractive)
            }
            .frame(width: motion.frame.width, height: max(0, motion.frame.height - topHeight), alignment: .top)
            .opacity(motion.contentOpacity)
            .clipped()
        }
        .frame(width: motion.frame.width, height: motion.frame.height, alignment: .top)
        .background(nativeSurface ? Color.clear : Color.black)
        .clipShape(nativeSurface ? AnyShape(Rectangle()) : AnyShape(islandShape))
        .overlay(alignment: .bottom) {
            if increasedContrast && model.presentation != .compact {
                islandShape
                    .stroke(rule, lineWidth: 1)
                    .clipShape(islandShape).allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .tint(model.preferences.values.accent.color)
        // Keep the rail attached to the screen edge while AppKit resizes ahead of a SwiftUI layout pass.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var statusRail: some View {
        let wing = max(22, (bodyWidth - model.notchGap) / 2)
        let geometry = motion.layout.railGeometry ?? RailGeometry(cubeWidth: 22, statusWidth: 20, clearance: 12)
        let available = max(22, wing - 2 * geometry.clearance)
        let count = CubeTimeline.visibleCount(total: model.cubes.count, wingWidth: available)
        let measured = PanelController.railGeometry(cubeCount: model.cubes.count, label: model.rail.label,
                                                   typography: model.typography, preferences: model.preferences.values,
                                                   displayScale: 24 / geometry.clearance)
        let ringWidth = CompactQuotaRing.diameter + model.preferences.values.ringStroke
        let textWidth = max(0, measured.statusWidth - ringWidth - model.preferences.values.statusGap)
        let displayedGroup = max(ringWidth, min(geometry.statusWidth, available))
        let labelOpacity = model.rail.label == nil ? 0 : RailGeometry.statusOpacity(
            availableWing: wing, displayedGroup: displayedGroup,
            requiredGroup: measured.statusWidth, clearance: geometry.clearance)
        return Button { model.clickIsland() } label: {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(Array(model.cubes.prefix(count))) { cube in
                        Group {
                            if model.glyphTheme == .cube {
                                CubeCompanion(descriptor: cube,
                                              paused: reduceMotion || !model.animationsEnabled || !model.preferences.values.cubeAnimationsEnabled || !model.preferences.values.showIsland,
                                              frozen: cubeFrozenOverride ?? model.isFixture)
                            } else {
                                Image(systemName: IslandDesign.symbol(cube.state))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(statusColor(cube.state))
                                    .contentTransition(.opacity)
                            }
                        }
                        .frame(width: 22, height: 22)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(cube.title), \(cube.state.label)")
                    }
                    if model.cubes.count > count {
                        Text("+\(model.cubes.count - count)")
                            .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(IslandDesign.secondary)
                    }
                }
                .frame(width: wing)
                Color.clear.frame(width: model.notchGap)
                ZStack(alignment: .trailing) {
                    if model.rail.label != nil {
                        CompactStatusFlip(label: compactLabel,
                                          font: IslandFont.font(weight: model.typography.statusWeight,
                                                                size: model.typography.statusSize,
                                                                family: model.preferences.values.fontFamily),
                                          motionEnabled: model.animationsEnabled,
                                          reduceMotion: reduceMotion,
                                          style: model.preferences.values.statusTransition,
                                          duration: model.preferences.values.statusDuration,
                                          blur: model.preferences.values.statusBlur)
                            .frame(width: textWidth)
                            .offset(x: -ringWidth - model.preferences.values.statusGap)
                            .opacity(labelOpacity)
                    }
                    CompactQuotaRing(quota: model.snapshot.quota,
                                         animationsEnabled: model.animationsEnabled,
                                         increasedContrast: increasedContrast,
                                         typography: model.typography,
                                         fontFamily: model.preferences.values.fontFamily,
                                         ringStroke: model.preferences.values.ringStroke)
                            .fixedSize()
                }
                .frame(width: displayedGroup, alignment: .trailing)
                .frame(width: wing)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Codex Island, \(model.rail.accessibleStatus), \(CompactQuotaState(quota: model.snapshot.quota).accessibilityLabel). Open task details")
    }

    private var preview: some View {
        Button { model.clickIsland() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(primary?.currentRequestTitle ?? "All quiet.")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let primary {
                    HStack(spacing: 6) {
                        ProjectFolderIcon().stroke(IslandDesign.secondary, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                            .frame(width: 13, height: 13).accessibilityHidden(true)
                        Text(primary.workspaceName).lineLimit(1)
                        Text("·")
                        TrayActivityText(state: primary.state, visible: model.preferences.values.showIsland && model.presentation == .preview && previewOpacity > 0.9,
                                         animationsEnabled: model.animationsEnabled)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
                }
                HStack {
                    Text("\(model.snapshot.activeChatSummary) · \(model.snapshot.attentionCount) attention")
                    Spacer()
                    Image(systemName: "arrow.down.right.and.arrow.up.left").rotationEffect(.degrees(180))
                }
                .font(.system(size: 10, weight: .medium)).foregroundStyle(IslandDesign.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Click to pin the expanded island")
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.snapshot.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(IslandDesign.amber)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(IslandDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                    pageContent
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .animation(labelAnimation, value: model.page)
            footer
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            if model.page != .activity {
                iconButton("chevron.left", "Back to activity") { model.page = .activity }
            }
            if model.page != .activity {
                Text(pageTitle).font(.system(size: 12, weight: .semibold))
            } else if primary == nil {
                Text("All quiet.").font(.system(size: 21, weight: .semibold))
            }
            Spacer()
            if model.page == .activity {
                iconButton("clock", "Recent tasks") { model.page = .recent }
            }
            iconButton("chevron.up", "Collapse island") { model.dismiss() }
        }
        .padding(.leading, 20).padding(.trailing, 14).frame(height: 40)
    }

    private var pageTitle: String {
        switch model.page {
        case .activity: "Codex"
        case .recent: "Recent tasks"
        case .question: "Your input"
        case .task: "Task details"
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch model.page {
        case .activity: activityPage
        case .recent:
            if model.snapshot.recentTasks.isEmpty { Text("No recent tasks").foregroundStyle(IslandDesign.secondary) }
            ForEach(model.snapshot.recentTasks) { taskRow($0) }
        case let .question(id):
            if let task = model.snapshot.tasks.first(where: { $0.id == id }), let question = task.pendingQuestion {
                questionPage(question, task: task)
            } else {
                Text("This question has been resolved.").font(.system(size: 14, weight: .medium))
                action("Back to activity", symbol: "arrow.left") { model.page = .activity }
            }
        case let .task(id):
            if let task = model.snapshot.tasks.first(where: { $0.id == id }) {
                taskDetails(task)
            } else {
                Text("This task is no longer available. Return to activity or refresh to check again.")
                    .font(.system(size: 12)).foregroundStyle(IslandDesign.secondary)
                action("Back to activity", symbol: "arrow.left") { model.page = .activity }
            }
        }
    }

    private var activityPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let primary {
                VStack(alignment: .leading, spacing: 10) {
                    Text(primary.currentRequestTitle)
                        .font(.system(size: 19, weight: .semibold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    action("Task details", symbol: "text.alignleft") { model.page = .task(primary.id) }
                    HStack(spacing: 6) {
                        Image(systemName: "folder").accessibilityHidden(true)
                        Text(primary.workspaceName).lineLimit(1)
                        Spacer()
                        Text(primary.updatedAt.formatted(.relative(presentation: .named))).lineLimit(1)
                    }
                    .font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: IslandDesign.symbol(primary.state)).foregroundStyle(IslandDesign.secondary)
                            TrayActivityText(state: primary.state, visible: model.preferences.values.showIsland && expandedInteractive && model.page == .activity,
                                             animationsEnabled: model.animationsEnabled)
                        }
                        Spacer()
                        Text("\(model.snapshot.activeChatSummary) · \(model.snapshot.attentionCount) attention")
                            .foregroundStyle(IslandDesign.secondary)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .animation(labelAnimation, value: primary.state)
                }
                if let question = primary.pendingQuestion {
                    action(question.header + " · Answer in Codex", symbol: "questionmark.bubble") {
                        model.page = .question(primary.id)
                    }
                }
            }
            dailySummary
            let others = model.snapshot.tasks.filter {
                $0.id != model.snapshot.primaryTaskID && ($0.state.isActive || $0.state.needsAttention)
            }
            if !others.isEmpty {
                rule.frame(height: 1)
                ForEach(others) { taskRow($0) }
            }
        }
    }

    private func taskRow(_ task: TaskSnapshot) -> some View {
        HStack(spacing: 4) {
        IslandButton(motionEnabled: model.animationsEnabled, action: {
            if task.pendingQuestion != nil { model.page = .question(task.id) }
            else { model.openCodex(taskID: task.id) }
        }) {
            HStack(spacing: 12) {
                Image(systemName: IslandDesign.symbol(task.state))
                    .font(.system(size: 13)).foregroundStyle(statusColor(task.state))
                    .frame(width: 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.cleanedTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("\(task.workspaceName) · \(task.state.label) · \(task.updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10)).foregroundStyle(IslandDesign.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: task.pendingQuestion != nil ? "chevron.right" : "arrow.up.right")
                    .font(.system(size: 9)).foregroundStyle(IslandDesign.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 8).frame(height: 48).contentShape(Rectangle())
        }
        .accessibilityLabel("\(task.cleanedTitle), \(task.workspaceName), \(task.state.label)")
        iconButton("text.alignleft", "Show task details") { model.page = .task(task.id) }
        }
    }

    private func taskDetails(_ task: TaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.cleanedTitle)
                .font(.system(size: 19, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let request = task.latestUserRequest, task.currentRequestTitle != task.cleanedTitle {
                Text("Latest request").font(.system(size: 11, weight: .medium)).foregroundStyle(IslandDesign.secondary)
                Text(request).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Label(task.state.label, systemImage: IslandDesign.symbol(task.state))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(statusColor(task.state))
            Text(task.workspacePath ?? "Unknown workspace")
                .font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(task.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
            if task.pendingQuestion != nil {
                action("View question", symbol: "questionmark.bubble") { model.page = .question(task.id) }
            }
            action("Open Codex", symbol: "arrow.up.right") { model.openCodex(taskID: task.id) }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            rule.frame(height: 1)
            if let quota = model.snapshot.quota {
                VStack(spacing: 6) {
                    HStack {
                        Text(quota.windowMinutes >= 1440 ? "\(quota.windowMinutes / 1440)-day quota" : "\(quota.windowMinutes / 60)-hour quota")
                            .foregroundStyle(IslandDesign.secondary)
                        Spacer()
                        Text("\(Int(quota.remainingPercent))% remaining")
                            .foregroundStyle(IslandDesign.quotaFooterColor(quota))
                            .monospacedDigit().contentTransition(.numericText())
                    }.font(.system(size: 11, weight: .medium))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(IslandDesign.quotaFooterColor(quota))
                            .scaleEffect(x: quota.remainingPercent / 100, y: 1, anchor: .leading)
                    }
                    .frame(height: 4)
                    .animation(labelAnimation, value: quota.remainingPercent)
                    .accessibilityLabel("\(Int(quota.remainingPercent)) percent of quota remaining")
                    if let reset = quota.resetAt {
                        Text("Resets \(reset.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(IslandDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("Quota unavailable").font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16)
    }

    private func questionPage(_ question: PendingQuestion, task: TaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.header).font(.system(size: 18, weight: .semibold))
            Text(question.prompt).font(.system(size: 13))
            Text("Select an option to open Codex, where you can submit your answer.")
                .font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
            ForEach(question.choices) { choice in
                IslandButton(motionEnabled: model.animationsEnabled, action: { model.openCodex(taskID: task.id) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(choice.label).font(.system(size: 12, weight: .semibold))
                        Text(choice.description).font(.system(size: 11)).foregroundStyle(IslandDesign.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(IslandDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            action("Other… in Codex", symbol: "arrow.up.right") { model.openCodex(taskID: task.id) }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        IslandButton(motionEnabled: model.animationsEnabled,
                     action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(IslandDesign.secondary).frame(width: 30, height: 30).contentShape(Rectangle())
        }.accessibilityLabel(label).help(label)
    }

    private var dailySummary: some View {
        let summary = DailySummary(stats: model.snapshot.dailyStats)
        var text = AttributedString(summary.sentence)
        text.foregroundColor = IslandDesign.secondary
        for value in [summary.turns, summary.duration] {
            if let range = text.range(of: value) {
                text[range].foregroundColor = .white
                text[range].font = .system(size: 12, weight: .medium)
            }
        }
        return Text(text).font(.system(size: 12)).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func action(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        IslandButton(motionEnabled: model.animationsEnabled, action: action) {
            HStack(spacing: 8) { Text(title); Image(systemName: symbol).font(.system(size: 10)) }
                .font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).frame(height: 32)
                .background(IslandDesign.surface, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}
