import SwiftUI

struct WizardView: View {
    @EnvironmentObject var state: AppState

    private let titles = [
        "Detect Claude Code",
        "Choose alarm video",
        "Notification events",
        "Install hooks",
        "Test alarm"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome — Claude Wakeup Alarm")
                    .font(.title2.weight(.bold))
                Text("Step \(state.wizardStep + 1) of \(titles.count): \(titles[state.wizardStep])")
                    .foregroundStyle(WATheme.muted)

                Group {
                    switch state.wizardStep {
                    case 0:
                        VStack(alignment: .leading, spacing: 8) {
                            Text(state.settingsExist ? "Claude settings found." : "Claude settings not found yet — install will create them.")
                            Text(SystemProbe.which("jq") != nil ? "jq is available." : "Install jq: brew install jq")
                        }
                    case 1:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Drop clips into media/ or browse after setup. Random mode uses whatever is there.")
                            Text("Clips found: \(state.mediaFiles.count)")
                            if let first = state.mediaFiles.first {
                                Text("Example: \(first.lastPathComponent)")
                                    .foregroundStyle(WATheme.muted)
                            }
                        }
                    case 2:
                        EventsView()
                            .frame(height: 220)
                    case 3:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Install hooks into Claude Code settings.")
                            HStack {
                                PrimaryButton(title: "Install Global") { state.installHooks(project: false) }
                                PrimaryButton(title: "Install Project") { state.installHooks(project: true) }
                            }
                            Text(state.hooksInstalled ? "Hooks installed." : "Hooks not installed yet.")
                                .foregroundStyle(state.hooksInstalled ? WATheme.accent : WATheme.warn)
                        }
                    default:
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Fire a test alarm now. It stops when you move the mouse or type.")
                            PrimaryButton(title: "TEST ALARM") { state.testAlarm() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(WATheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HStack {
                    if state.wizardStep > 0 {
                        PrimaryButton(title: "Back") { state.wizardStep -= 1 }
                    }
                    Spacer()
                    if state.wizardStep < titles.count - 1 {
                        PrimaryButton(title: "Next") { state.wizardStep += 1 }
                    } else {
                        PrimaryButton(title: "Finish") { state.finishWizard() }
                    }
                }
            }
            .padding(28)
            .frame(width: 560)
            .background(WATheme.bg)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WATheme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
