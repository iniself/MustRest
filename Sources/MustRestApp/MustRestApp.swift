import SwiftUI
import AppKit
import MustRest

@main
struct MustRestApp: App {
    @StateObject private var engine = PomodoroEngine()
    @StateObject private var store = PomodoroStore.shared
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra(
            engine.currentTask?.name ?? "MustRest",
            systemImage: "timer",
            isInserted: Binding.constant(true)
        ) {
            Button {
                if engine.isPaused {
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
