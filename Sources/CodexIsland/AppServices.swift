import AppKit
import Combine
import ServiceManagement
import SwiftUI
import Darwin

@MainActor
enum CodexInstallation {
    static func applicationURL() -> URL? {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") { return url }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Applications/Codex.app"), URL(fileURLWithPath: "/Applications/Codex.app")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func executableCandidates() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var applications = [applicationURL(), NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat")].compactMap { $0 }
        applications += ["/Applications/Codex.app", "/Applications/ChatGPT.app"].map { URL(fileURLWithPath: $0) }
        applications += ["Applications/Codex.app", "Applications/ChatGPT.app"].map { home.appendingPathComponent($0) }
        return applications.map { $0.appendingPathComponent("Contents/Resources/codex").path } +
            [home.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
    }
}

/// One per user, including command-line development launches and installed variants.
final class IslandInstanceLock {
    private var descriptor: Int32 = -1
    func acquire() -> Bool {
        descriptor = open("/tmp/com.codexisland.\(getuid()).lock", O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
        close(descriptor); descriptor = -1
        return false
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}

@MainActor
final class AppServices: NSObject, ObservableObject {
    let preferences: PreferencesStore
    let model: AppModel
    @Published var loginEnabled = false
    @Published var loginMessage: String?
    private let launchServicesEnabled: Bool
    private var panel: PanelController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var quitting = false
    private var visibilityItem: NSMenuItem?
    private var preferenceSubscription: AnyCancellable?
    var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") +
        " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local") + ")"
    }

    init(launchServicesEnabled: Bool = true, preferences: PreferencesStore? = nil) {
        self.launchServicesEnabled = launchServicesEnabled
        self.preferences = preferences ?? PreferencesStore(defaults: launchServicesEnabled ? PreferencesStore.appDefaults : nil)
        model = AppModel(fixture: launchServicesEnabled ? nil : IslandFixtures.snapshot("idle"), preferences: self.preferences)
        super.init()
        if launchServicesEnabled { refreshLoginStatus() }
    }

    func start() {
        guard panel == nil, launchServicesEnabled else { return }
        panel = PanelController(model: model)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Codex Island")
        let menu = NSMenu()
        func entry(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
            let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
            value.target = self; menu.addItem(value); return value
        }
        _ = entry("Settings…", #selector(showSettings), ",")
        visibilityItem = entry("Hide Island", #selector(toggleVisibility))
        _ = entry("Open Codex", #selector(openCodex))
        menu.addItem(.separator())
        _ = entry("Quit Codex Island", #selector(quit), "q")
        item.menu = menu; statusItem = item
        preferenceSubscription = preferences.$values.sink { [weak self] value in
            self?.visibilityItem?.title = value.showIsland ? "Hide Island" : "Show Island"
        }
        model.start()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Codex Island Settings"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 820, height: 620)
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, services: self))
            window.setFrameAutosaveName("CodexIsland.Settings")
            window.center()
            settingsWindow = window
        }
        refreshLoginStatus()
        model.dismiss()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleVisibility() { preferences.values.showIsland.toggle() }
    @objc func openCodex() { model.openCodex() }
    func refresh() async { await model.refresh() }
    func setLoginEnabled(_ enabled: Bool) {
        guard launchServicesEnabled else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginMessage = nil
        } catch { loginMessage = "Could not change Launch at Login: \(error.localizedDescription)" }
        refreshLoginStatus()
    }
    private func refreshLoginStatus() {
        guard launchServicesEnabled else { return }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginMessage = "Allow Codex Island in System Settings → General → Login Items."
        }
    }
    @objc func quit() {
        guard !quitting else { return }
        quitting = true
        panel?.shutdown()
        settingsWindow?.close()
        Task { @MainActor in
            await model.stop()
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            NSApp.terminate(nil)
        }
    }
}
