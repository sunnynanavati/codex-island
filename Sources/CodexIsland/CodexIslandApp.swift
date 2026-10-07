import AppKit
import SwiftUI
import Carbon

@main
enum CodexIslandApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panelController: PanelController?
    private var services: AppServices?
    private let instanceLock = IslandInstanceLock()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        IslandFont.register()
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--record-motion"), arguments.indices.contains(index + 1) {
            Task { @MainActor in
                do { try await IslandMotionRecording.record(to: URL(fileURLWithPath: arguments[index + 1])) }
                catch { AppLog.write("Motion recording failed: \(error.localizedDescription)") }
                NSApp.terminate(nil)
            }
            return
        }
        if arguments.contains("--diagnose") {
            Task {
                do {
                    let snapshot = try await CodexDataStore().loadSnapshot()
                    AppLog.write("Diagnostic: \(snapshot.tasks.count) tasks readable")
                } catch { AppLog.write("Diagnostic: \(error.localizedDescription)") }
                if let quota = await LiveQuota().quota() {
                    AppLog.write("Diagnostic: live account quota \(quota.remainingPercent)% remaining, \(quota.windowMinutes)-minute window")
                } else { AppLog.write("Diagnostic: live account quota unavailable") }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(index + 1) {
            Task { @MainActor in
                do { try await IslandPreviewRenderer.render(to: URL(fileURLWithPath: arguments[index + 1])) }
                catch { AppLog.write("Preview rendering failed: \(error.localizedDescription)") }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = arguments.firstIndex(of: "--render-settings"), arguments.indices.contains(index + 1) {
            Task { @MainActor in
                let services = AppServices(launchServicesEnabled: false)
                let root = SettingsView(preferences: services.preferences, services: services)
                let host = NSHostingView(rootView: root)
                let bounds = NSRect(x: 0, y: 0, width: 900, height: 720)
                let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host; host.frame = bounds
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(400))
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: bounds) {
                    host.cacheDisplay(in: bounds, to: bitmap)
                    if let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: arguments[index + 1]))
                    }
                }
                window.close(); NSApp.terminate(nil)
            }
            return
        }
        AppLog.write("Codex Island \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") started (local read-only monitor)")
        let scenario = arguments.firstIndex(of: "--preview-state").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
        if scenario == nil {
            guard instanceLock.acquire() else {
                DistributedNotificationCenter.default().postNotificationName(.init("CodexIsland.openSettings"), object: nil)
                NSApp.terminate(nil); return
            }
            let services = AppServices()
            self.services = services
            installMenu(services)
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(reopenSettings),
                                                                name: .init("CodexIsland.openSettings"), object: nil)
            services.start()
            let login = NSAppleEventManager.shared().currentAppleEvent?
                .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            if !arguments.contains("--background") && !login { services.showSettings() }
            return
        }
        let model = AppModel(fixture: scenario.map { IslandFixtures.snapshot($0) })
        if scenario != nil { model.presentation = .pinned }
        self.model = model
        panelController = PanelController(model: model)
        model.start()
    }

    @objc private func reopenSettings() { services?.showSettings() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        services?.showSettings(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func installMenu(_ services: AppServices) {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        for (title, action, key) in [("Settings…", #selector(AppServices.showSettings), ","),
                                     ("Quit Codex Island", #selector(AppServices.quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = services; app.addItem(item)
        }
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }
}
