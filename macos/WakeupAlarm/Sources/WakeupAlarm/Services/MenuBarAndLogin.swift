import AppKit
import Foundation
import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Fallback: LaunchAgent plist when not running as a proper .app bundle
                setLaunchAgent(enabled: enabled)
            }
        } else {
            setLaunchAgent(enabled: enabled)
        }
    }

    func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled { return true }
        }
        return FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.claude.wakeup-alarm.manager.plist")
    }

    private func setLaunchAgent(enabled: Bool) {
        let url = launchAgentURL
        if !enabled {
            _ = ShellRunner.run("/bin/launchctl", arguments: ["unload", url.path])
            try? FileManager.default.removeItem(at: url)
            return
        }
        let exe = Bundle.main.executableURL?.path
            ?? CommandLine.arguments.first
            ?? WakeupPaths.home.appendingPathComponent("Launch-WakeupAlarm.command").path
        let home = WakeupPaths.home.path
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.claude.wakeup-alarm.manager</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(exe)</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>WAKEUP_HOME</key>
            <string>\(home)</string>
          </dict>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? plist.write(to: url, atomically: true, encoding: .utf8)
        _ = ShellRunner.run("/bin/launchctl", arguments: ["load", url.path])
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var item: NSStatusItem?
    var onOpen: (() -> Void)?
    var onToggle: (() -> Void)?
    var onTest: (() -> Void)?
    var onQuit: (() -> Void)?
    private var enabledTitle = "Disable Alarm"

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "⏰"
            button.toolTip = "Claude Wakeup Alarm"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Claude Wakeup Alarm", action: #selector(open), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: enabledTitle, action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Test Alarm", action: #selector(test), keyEquivalent: "t"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        self.item = item
    }

    func setAlarmEnabled(_ enabled: Bool) {
        enabledTitle = enabled ? "Disable Alarm" : "Enable Alarm"
        item?.menu?.item(at: 1)?.title = enabledTitle
    }

    @objc private func open() { onOpen?() }
    @objc private func toggle() { onToggle?() }
    @objc private func test() { onTest?() }
    @objc private func quit() { onQuit?() }
}
