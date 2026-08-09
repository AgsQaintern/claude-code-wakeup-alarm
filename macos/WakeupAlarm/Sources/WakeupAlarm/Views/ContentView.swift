import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            WATheme.bg.ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    header
                    Divider().overlay(WATheme.border)
                    pageBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let toast = state.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(state.toastOK ? WATheme.accent : WATheme.warn)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(WATheme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(WATheme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if state.showWizard {
                WizardView()
            }
        }
        .foregroundStyle(WATheme.text)
        .frame(minWidth: 980, minHeight: 640)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MANAGER")
                .font(.caption2.weight(.bold))
                .foregroundStyle(WATheme.muted)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)
            ForEach(AppState.Page.allCases) { p in
                Button {
                    state.page = p
                } label: {
                    Text(p.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(state.page == p ? WATheme.accent.opacity(0.15) : Color.clear)
                        .foregroundStyle(state.page == p ? WATheme.accent : WATheme.text)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 180)
        .background(WATheme.sidebar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Wakeup Alarm")
                    .font(.title3.weight(.bold))
                Text("macOS manager — hooks keep working when this window is closed")
                    .font(.caption)
                    .foregroundStyle(WATheme.muted)
            }
            Spacer()
            Pill(title: state.config.enabled ? "Alarm ON" : "Alarm OFF", ok: state.config.enabled)
            Pill(title: state.hooksInstalled ? "Hooks OK" : "Hooks missing", ok: state.hooksInstalled)
            Pill(title: state.showWizard ? "Setup" : "Ready", ok: !state.showWizard)
        }
        .padding(16)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch state.page {
        case .dashboard: DashboardView()
        case .events: EventsView()
        case .alarm: AlarmView()
        case .videos: VideosView()
        case .logs: LogsView()
        case .setup: SetupView()
        case .settings: SettingsView()
        }
    }
}
