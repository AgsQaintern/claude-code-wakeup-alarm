import AppKit
import SwiftUI

@main
struct WakeupAlarmApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .background(WindowAccessor { window in
                    appDelegate.state = state
                    appDelegate.mainWindow = window
                    window?.title = "Claude Wakeup Alarm"
                })
                .opacity(state.windowVisible ? 1 : 0)
                .allowsHitTesting(state.windowVisible)
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Claude Wakeup Alarm") {
                    state.reallyQuit = true
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var state: AppState?
    weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state?.windowVisible = true
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        state?.handleClose() ?? true
    }
}

/// Attach window delegate once the SwiftUI window exists.
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            let window = view.window
            window?.delegate = (NSApp.delegate as? AppDelegate)
            onResolve(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}
