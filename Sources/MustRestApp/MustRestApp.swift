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
                Text(engine.phase == .working || engine.phase == .breaking ? "暂停" : "继续")
            }

            Button {
                NSLog("[MenuBarExtra] Settings button clicked")
                windowManager.showSettings(engine: engine, store: store)
            } label: {
                Text("设置...")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
            }
        }
        .environmentObject(engine)
        .environmentObject(store)
        .environmentObject(windowManager)
    }
}
