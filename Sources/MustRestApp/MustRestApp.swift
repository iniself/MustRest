import SwiftUI
import AppKit
import MustRest

@main
struct MustRestApp: App {
    @StateObject private var engine = PomodoroEngine()
    @StateObject private var store = PomodoroStore.shared
    @StateObject private var windowManager = WindowManager()

    /// Stable binding instance: creating a new `Binding` on every body
    /// evaluation makes SwiftUI build a new menu on each render.
    private static let menuInsertBinding = Binding<Bool>(get: { true }, set: { _ in })

    var body: some Scene {
        MenuBarExtra(
            engine.currentTask?.name ?? "MustRest",
            systemImage: "timer",
            isInserted: MustRestApp.menuInsertBinding
        ) {
            Button {
                // Toggle the running timer: working/breaking -> pause, paused ->
                // resume, idle -> start the first task.
                if engine.phase == .working || engine.phase == .breaking {
                    engine.pause()
                } else if engine.phase == .paused {
                    engine.resume()
                } else if let firstTask = store.settings.tasks.first {
                    engine.start(task: firstTask)
                }
            } label: {
                // Button title: "Start" when idle, "Pause" while running, "Resume" when paused.
                if engine.phase == .working || engine.phase == .breaking {
                    Label("暂停", systemImage: "pause.circle")
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
                NSLog("[MenuBarExtra] Settings button clicked")
                windowManager.showSettings(engine: engine, store: store)
            } label: {
                Label("设置...", systemImage: "gearshape")
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
