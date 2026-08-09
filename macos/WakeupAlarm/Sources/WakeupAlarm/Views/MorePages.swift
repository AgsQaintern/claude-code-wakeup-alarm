import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideosView: View {
    @EnvironmentObject var state: AppState
    @State private var selected: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $state.config.videoMode) {
                Text("Random from media/").tag("random")
                Text("Fixed video").tag("fixed")
            }
            .pickerStyle(.radioGroup)

            Picker("Player", selection: $state.config.player) {
                Text("Auto").tag("auto")
                Text("FFplay").tag("ffplay")
                Text("QuickTime").tag("quicktime")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            List(selection: $selected) {
                ForEach(state.mediaFiles, id: \.path) { url in
                    Text(url.lastPathComponent).tag(url)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 220)
            .background(WATheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                PrimaryButton(title: "Browse…") { browse() }
                PrimaryButton(title: "Use Selected") {
                    if let selected {
                        state.config.video = selected.path
                        state.config.videoMode = "fixed"
                        state.saveConfig()
                    }
                }
                PrimaryButton(title: "Preview") {
                    state.testAlarm(video: selected?.path ?? state.config.video, preview: true)
                }
                PrimaryButton(title: "Test Video") {
                    state.testAlarm(video: selected?.path ?? state.config.video)
                }
                PrimaryButton(title: "Remove", destructive: true) {
                    if let selected { state.removeVideo(selected) }
                }
                PrimaryButton(title: "SAVE") { state.saveConfig() }
            }

            if state.config.videoMode == "fixed" && !state.config.video.isEmpty {
                Text("Fixed: \(state.config.video)")
                    .font(.caption)
                    .foregroundStyle(WATheme.muted)
            }
            Spacer()
        }
        .padding(20)
        .onAppear { state.refreshStatic() }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            state.importVideo(from: url)
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PrimaryButton(title: "Refresh") { state.refreshLogs() }
                PrimaryButton(title: "Clear View") { state.logRows = [] }
                PrimaryButton(title: "Open Log File") {
                    NSWorkspace.shared.open(SystemProbe.logURL(for: state.config))
                }
                Spacer()
                Text(SystemProbe.logURL(for: state.config).path)
                    .font(.caption2)
                    .foregroundStyle(WATheme.muted)
                    .lineLimit(1)
            }
            List(state.logRows) { row in
                HStack(alignment: .top) {
                    Text(row.timestamp)
                        .font(.caption.monospaced())
                        .foregroundStyle(WATheme.muted)
                        .frame(width: 140, alignment: .leading)
                    Text(row.body)
                        .font(.caption.monospaced())
                }
            }
            .listStyle(.inset)
        }
        .padding(20)
        .onAppear { state.refreshLogs() }
    }
}

struct SetupView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install & verify hooks")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                Card(title: "Claude settings.json") {
                    Text(state.settingsExist ? "Present" : "Missing").font(.title3.weight(.semibold))
                }
                Card(title: "Wakeup hooks") {
                    Text(state.hooksInstalled ? "Installed" : "Not installed").font(.title3.weight(.semibold))
                }
                Card(title: "jq") {
                    Text(SystemProbe.which("jq") != nil ? "Found" : "Missing (brew install jq)").font(.title3.weight(.semibold))
                }
                Card(title: "ffplay") {
                    Text(state.hasFFplay ? "Found" : "Optional — QuickTime fallback").font(.title3.weight(.semibold))
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Install Global") { state.installHooks(project: false) }
                PrimaryButton(title: "Install Project") { state.installHooks(project: true) }
                PrimaryButton(title: "Uninstall Global", destructive: true) { confirmUninstall(project: false) }
                PrimaryButton(title: "Uninstall Project", destructive: true) { confirmUninstall(project: true) }
                PrimaryButton(title: "Verify") {
                    state.refreshStatic()
                    state.showToast(state.hooksInstalled ? "Hooks verified" : "Hooks not found", ok: state.hooksInstalled)
                }
            }
            Text("Restart Claude Code after installing — hooks load at session start.")
                .font(.caption)
                .foregroundStyle(WATheme.muted)
            Spacer()
        }
        .padding(20)
    }

    private func confirmUninstall(project: Bool) {
        let alert = NSAlert()
        alert.messageText = "Uninstall wakeup hooks?"
        alert.informativeText = "Only wakeup.sh entries are removed. Other Claude settings stay intact."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            state.uninstallHooks(project: project)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Hook scope") {
                Picker("Scope", selection: $state.config.ui.scope) {
                    Text("Global").tag("global")
                    Text("Project").tag("project")
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("Project path", text: $state.config.ui.projectPath)
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            state.config.ui.projectPath = url.path
                        }
                    }
                }
            }
            Section("Manager") {
                Toggle("Start manager at login", isOn: $state.config.ui.startAtLogin)
                Toggle("Minimize to menu bar on close", isOn: $state.config.ui.minimizeToTray)
            }
            PrimaryButton(title: "SAVE SETTINGS") {
                state.applyStartAtLogin()
                state.saveConfig()
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }
}
