import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case events = "Events"
        case alarm = "Alarm"
        case videos = "Videos"
        case logs = "Logs"
        case setup = "Setup"
        case settings = "Settings"
        var id: String { rawValue }
    }

    @Published var config: WakeupConfig
    @Published var page: Page = .dashboard
    @Published var toast: String?
    @Published var toastOK = true
    @Published var showWizard: Bool
    @Published var wizardStep = 0
    @Published var idleSecs = 0
    @Published var status = EngineStatus.idle
    @Published var lockHeld = false
    @Published var hooksInstalled = false
    @Published var settingsExist = false
    @Published var hasFFplay = false
    @Published var mediaFiles: [URL] = []
    @Published var logRows: [LogRow] = []
    @Published var windowVisible = true
    @Published var reallyQuit = false

    private var timer: AnyCancellable?
    private var toastWork: DispatchWorkItem?

    init() {
        let cfg = ConfigStore.load()
        self.config = cfg
        self.showWizard = !cfg.ui.firstRunCompleted
        refreshStatic()
        startPolling()
        setupMenuBar()
    }

    var projectPath: String {
        if !config.ui.projectPath.isEmpty { return config.ui.projectPath }
        return WakeupPaths.home.path
    }

    func showToast(_ message: String, ok: Bool = true) {
        toast = message
        toastOK = ok
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    func saveConfig(silent: Bool = false) {
        do {
            try ConfigStore.save(config)
            if !silent { showToast("Settings saved") }
            refreshStatic()
            MenuBarController.shared.setAlarmEnabled(config.enabled)
        } catch {
            showToast("Could not save settings", ok: false)
        }
    }

    func refreshStatic() {
        hasFFplay = SystemProbe.which("ffplay") != nil
        hooksInstalled = SystemProbe.hooksInstalled(projectPath: projectPath, scope: config.ui.scope)
        settingsExist = SystemProbe.claudeSettingsExist(projectPath: projectPath, scope: config.ui.scope)
        mediaFiles = SystemProbe.listMedia()
        MenuBarController.shared.setAlarmEnabled(config.enabled)
    }

    func refreshLive() {
        idleSecs = SystemProbe.idleSeconds()
        status = SystemProbe.readStatus()
        lockHeld = SystemProbe.lockHeld()
        hooksInstalled = SystemProbe.hooksInstalled(projectPath: projectPath, scope: config.ui.scope)
    }

    func refreshLogs() {
        logRows = SystemProbe.readLogTail(SystemProbe.logURL(for: config))
    }

    private func startPolling() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshLive()
            }
    }

    private func setupMenuBar() {
        let mb = MenuBarController.shared
        mb.setup()
        mb.onOpen = { [weak self] in
            self?.windowVisible = true
            NSApp.activate(ignoringOtherApps: true)
        }
        mb.onToggle = { [weak self] in
            guard let self else { return }
            self.config.enabled.toggle()
            self.saveConfig(silent: true)
            self.showToast(self.config.enabled ? "Alarm enabled" : "Alarm disabled")
        }
        mb.onTest = { [weak self] in self?.testAlarm() }
        mb.onQuit = { [weak self] in
            self?.reallyQuit = true
            NSApp.terminate(nil)
        }
    }

    // MARK: - Engine actions

    func testAlarm(video: String? = nil, preview: Bool = false) {
        var args = ["test_alarm", "--immediate", "--force"]
        if preview { args.append("--preview") }
        if let video, !video.isEmpty {
            args.append(contentsOf: ["--video", video])
        }
        ShellRunner.runDetached("/bin/bash", arguments: [WakeupPaths.playSh.path] + args)
        showToast(preview ? "Preview started" : "Test alarm started")
    }

    func simulate(fixture: String) {
        let path = WakeupPaths.fixturesDir.appendingPathComponent(fixture).path
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            showToast("Fixture missing: \(fixture)", ok: false)
            return
        }
        _ = ShellRunner.run(
            "/bin/bash",
            arguments: [WakeupPaths.wakeupSh.path],
            stdin: data,
            cwd: WakeupPaths.home
        )
        showToast("Simulated \(fixture)")
    }

    func installHooks(project: Bool) {
        var args: [String] = [WakeupPaths.installSh.path]
        if project {
            args.append(contentsOf: ["--project", projectPath])
            config.ui.scope = "project"
            config.ui.projectPath = projectPath
        } else {
            config.ui.scope = "global"
        }
        let r = ShellRunner.run("/bin/bash", arguments: args, cwd: WakeupPaths.home)
        if r.exitCode == 0 {
            saveConfig(silent: true)
            refreshStatic()
            showToast("Hooks installed")
        } else {
            showToast(r.stderr.isEmpty ? "Install failed" : r.stderr, ok: false)
        }
    }

    func uninstallHooks(project: Bool) {
        var args: [String] = [WakeupPaths.uninstallSh.path]
        if project {
            args.append(contentsOf: ["--project", projectPath])
        }
        let r = ShellRunner.run("/bin/bash", arguments: args, cwd: WakeupPaths.home)
        if r.exitCode == 0 {
            refreshStatic()
            showToast("Hooks removed")
        } else {
            showToast(r.stderr.isEmpty ? "Uninstall failed" : r.stderr, ok: false)
        }
    }

    func importVideo(from source: URL) {
        let destDir = WakeupPaths.mediaURL
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            mediaFiles = SystemProbe.listMedia()
            showToast("Video added")
        } catch {
            showToast("Could not copy video", ok: false)
        }
    }

    func removeVideo(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            if config.video == url.path {
                config.video = ""
                config.videoMode = "random"
                saveConfig(silent: true)
            }
            mediaFiles = SystemProbe.listMedia()
            showToast("Video removed")
        } catch {
            showToast("Could not remove video", ok: false)
        }
    }

    func applyStartAtLogin() {
        LoginItemManager.shared.setEnabled(config.ui.startAtLogin)
    }

    func finishWizard() {
        config.ui.firstRunCompleted = true
        showWizard = false
        saveConfig(silent: true)
        showToast("Claude Wakeup Alarm is ready.")
    }

    func handleClose() -> Bool {
        if reallyQuit { return true }
        if config.ui.minimizeToTray {
            windowVisible = false
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Close Claude Wakeup Alarm?"
        alert.informativeText = "Hooks keep working either way. Hide to the menu bar, or quit the manager."
        alert.addButton(withTitle: "Hide to Menu Bar")
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            windowVisible = false
            return false
        case .alertSecondButtonReturn:
            reallyQuit = true
            return true
        default:
            return false
        }
    }
}
