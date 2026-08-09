import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Alarm enabled", isOn: Binding(
                    get: { state.config.enabled },
                    set: {
                        state.config.enabled = $0
                        state.saveConfig(silent: true)
                        state.showToast($0 ? "Alarm enabled" : "Alarm disabled")
                    }
                ))
                .toggleStyle(.switch)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Card(title: "Claude settings") {
                        Text(state.settingsExist ? "Found" : "Missing").font(.headline)
                    }
                    Card(title: "Hooks") {
                        Text(state.hooksInstalled ? "Installed" : "Not installed").font(.headline)
                    }
                    Card(title: "Player") {
                        Text(state.config.player + (state.hasFFplay ? " · ffplay" : " · QT")).font(.headline)
                    }
                    Card(title: "Idle") {
                        Text("\(state.idleSecs)s").font(.headline)
                    }
                    Card(title: "Engine") {
                        Text(state.status.state).font(.headline)
                    }
                    Card(title: "Lock") {
                        Text(state.lockHeld ? "Held" : "Free").font(.headline)
                    }
                    Card(title: "Last trigger") {
                        Text(state.status.trigger.isEmpty ? "—" : state.status.trigger).font(.headline)
                    }
                    Card(title: "Config") {
                        Text(WakeupPaths.configURL.lastPathComponent).font(.headline)
                    }
                }

                HStack(spacing: 10) {
                    PrimaryButton(title: "TEST ALARM") { state.testAlarm() }
                    PrimaryButton(title: "Simulate Permission") { state.simulate(fixture: "permission_prompt.json") }
                    PrimaryButton(title: "Needs Input") { state.simulate(fixture: "agent_needs_input.json") }
                    PrimaryButton(title: "Completed") { state.simulate(fixture: "agent_completed.json") }
                    PrimaryButton(title: "Finished") { state.simulate(fixture: "stop.json") }
                }

                Card(title: "Live status") {
                    Text("State: \(state.status.state)  ·  Idle: \(state.idleSecs)s  ·  Video: \(state.status.video.isEmpty ? "—" : URL(fileURLWithPath: state.status.video).lastPathComponent)")
                        .font(.subheadline)
                        .foregroundStyle(WATheme.muted)
                }
            }
            .padding(20)
        }
    }
}

struct EventsView: View {
    @EnvironmentObject var state: AppState

    private let labels: [(String, String)] = [
        ("permission_prompt", "Permission Required"),
        ("idle_prompt", "Idle / Waiting"),
        ("agent_needs_input", "Agent Needs Input"),
        ("agent_completed", "Agent Completed"),
        ("stop", "Claude Finished")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which Claude moments arm the alarm")
                .font(.headline)
            Text("Changes save immediately into config.json.")
                .font(.caption)
                .foregroundStyle(WATheme.muted)
            ForEach(labels, id: \.0) { key, label in
                Toggle(label, isOn: Binding(
                    get: { state.config.events.contains(key) },
                    set: { on in
                        if on {
                            if !state.config.events.contains(key) { state.config.events.append(key) }
                        } else {
                            state.config.events.removeAll { $0 == key }
                        }
                        state.saveConfig(silent: true)
                        state.showToast("Settings saved")
                    }
                ))
            }
            Spacer()
        }
        .padding(20)
    }
}

struct AlarmView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Timing") {
                stepper("Grace period (s)", value: $state.config.delaySecs)
                stepper("Idle threshold (s)", value: $state.config.idleSecs)
                stepper("Return detection (s)", value: $state.config.returnSecs)
                stepper("Max duration (s)", value: $state.config.maxSecs)
            }
            Section("Behavior") {
                Toggle("Loop until return", isOn: $state.config.loop)
                Toggle("Alarm enabled", isOn: $state.config.enabled)
                HStack {
                    Text("Volume override (optional)")
                    TextField("empty = leave alone", value: Binding(
                        get: { state.config.volume },
                        set: { state.config.volume = $0 }
                    ), format: .number)
                    .frame(width: 80)
                }
            }
            PrimaryButton(title: "SAVE SETTINGS") { state.saveConfig() }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private func stepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...3600) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundStyle(WATheme.muted)
            }
        }
    }
}
