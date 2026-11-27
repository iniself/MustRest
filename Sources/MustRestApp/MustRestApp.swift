import SwiftUI
import AppKit
import MustRest

@main
struct MustRestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine: PomodoroEngine
    @StateObject private var store: PomodoroStore
    @StateObject private var windowManager: WindowManager

    init() {
        let engine = PomodoroEngine()
        let store = PomodoroStore.shared
        _engine = StateObject(wrappedValue: engine)
        _store = StateObject(wrappedValue: store)
        _windowManager = StateObject(wrappedValue: WindowManager())

        // A warning notification already handed to the system survives app
        // termination, so drop any stale one from a previous session and
        // cancel the pending warning when the app quits. Otherwise the user
        // gets a "break is about to start" banner while the app is closed.
        engine.cancelPendingOverlayWarning()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            engine.cancelPendingOverlayWarning()
        }

        // Automatically start the pomodoro countdown on launch so the user
        // does not have to press the menu "开始" button manually after every
        // launch.
        DispatchQueue.main.async {
            engine.startAll(tasks: store.settings.tasks)
        }
    }

    /// Stable binding instance: creating a new `Binding` on every body
    /// evaluation makes SwiftUI build a new menu on each render.
    private static let menuInsertBinding = Binding<Bool>(get: { true }, set: { _ in })

    /// True while a pomodoro run is actively counting down, i.e. right after
    /// the user pressed start or resume.
    private var isTiming: Bool {
        engine.phase == .working || engine.phase == .breaking
    }

    var body: some Scene {
        MenuBarExtra(
            engine.currentTask?.name ?? "MustRest",
            systemImage: isTiming ? "hourglass" : "timer",
            isInserted: MustRestApp.menuInsertBinding
        ) {
            Button {
                // Toggle the running timer: working/breaking -> pause, paused ->
                // resume, idle -> start all tasks in parallel.
                if engine.phase == .working || engine.phase == .breaking {
                    engine.pause()
                } else if engine.phase == .paused {
                    engine.resume()
                } else {
                    // Start a fresh pomodoro run for every task so all of them
                    // count down in parallel from now.
                    engine.startAll(tasks: store.settings.tasks)
                }
            } label: {
                // While a pomodoro is counting down (after start / resume) the
                // icon becomes a timer icon to represent the running state.
                if isTiming {
                    Label("暂停", systemImage: "hourglass")
                        .labelStyle(.titleAndIcon)
                } else if engine.phase == .paused {
                    Label("继续", systemImage: "play.circle")
                        .labelStyle(.titleAndIcon)
                } else {
                    Label("开始", systemImage: "play.circle")
                        .labelStyle(.titleAndIcon)
                }
            }

            Button {
                windowManager.showSettings(engine: engine, store: store)
            } label: {
                Label("设置...", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }

            Button {
                windowManager.showAbout()
            } label: {
                Label("关于...", systemImage: "info.circle")
                    .labelStyle(.titleAndIcon)
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .labelStyle(.titleAndIcon)
            }
        }
        .environmentObject(engine)
        .environmentObject(store)
        .environmentObject(windowManager)
    }
}
