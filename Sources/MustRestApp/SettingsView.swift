import SwiftUI
import AppKit
import MustRest

struct SettingsView: View {
    @EnvironmentObject var engine: PomodoroEngine
    @EnvironmentObject var store: PomodoroStore
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("设置")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                Button {
                    windowManager.closeSettings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            ScrollView {
                VStack(spacing: 24) {
                    // Section 1: Reminder Settings
                    VStack(alignment: .leading, spacing: 8) {
                        Text("提醒方式")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Form {
                            Toggle(store.settings.reminderMethod.displayName, isOn: Binding(
                                get: { store.settings.reminderMethod == .overlay },
                                set: { newValue in
                                    var newSettings = store.settings
                                    newSettings.reminderMethod = newValue ? .overlay : .banner
                                    store.saveSettings(newSettings)
                                }
                            ))
                        }
                        .formStyle(.grouped)
                    }

                    // Section 2: Task Management
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("任务列表")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: addTask) {
                                Label("添加", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        VStack(spacing: 12) {
                            ForEach(store.settings.tasks) { task in
                                TaskRowView(task: task)
                            }

                            if store.settings.tasks.isEmpty {
                                Text("暂无任务")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            Divider()
            HStack {
                Spacer()
                Button("保存并关闭") {
                    store.saveSettings(store.settings)
                    windowManager.closeSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func addTask() {
        var newSettings = store.settings
        let newTask = Task(name: "新任务", workIntervalSeconds: 15 * 60, breakDurationSeconds: 15)
        newSettings.tasks.append(newTask)
        store.saveSettings(newSettings)
        // The newly added task becomes the one the menu bar toggle runs next.
        engine.setCurrentTask(newTask)
    }

    private func removeTask(_ task: Task) {
        var newSettings = store.settings
        newSettings.tasks.removeAll { $0.id == task.id }
        store.saveSettings(newSettings)
    }
}

struct TaskRowView: View {
    @EnvironmentObject var store: PomodoroStore
    let task: Task

    // Local draft state backing the text fields so that every keystroke is
    // reflected immediately and the field keeps its first responder status.
    @State private var nameText: String
    @State private var workMinutes: Double
    @State private var breakSeconds: Double

    init(task: Task) {
        self.task = task
        _nameText = State(initialValue: task.name)
        _workMinutes = State(initialValue: task.workIntervalSeconds / 60)
        _breakSeconds = State(initialValue: task.breakDurationSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "timer.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)

                TextField("任务名称", text: nameBinding)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Button(action: { removeTask(task) }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("工作 (分)").font(.caption2).foregroundColor(.secondary)
                    TextField("", value: workBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading) {
                    Text("休息 (秒)").font(.caption2).foregroundColor(.secondary)
                    TextField("", value: breakBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
    }

    // Text fields read from / write to local draft state, then propagate the
    // change into the task held by the store.
    private var nameBinding: Binding<String> {
        Binding(
            get: { nameText },
            set: { newValue in
                nameText = newValue
                updateTask { $0.name = newValue }
            }
        )
    }

    private var workBinding: Binding<Double> {
        Binding(
            get: { workMinutes },
            set: { newValue in
                workMinutes = newValue
                updateTask { $0.workIntervalSeconds = newValue * 60 }
            }
        )
    }

    private var breakBinding: Binding<Double> {
        Binding(
            get: { breakSeconds },
            set: { newValue in
                breakSeconds = newValue
                updateTask { $0.breakDurationSeconds = newValue }
            }
        )
    }

    private func updateTask(_ mutate: (inout Task) -> Void) {
        guard let index = store.settings.tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var newSettings = store.settings
        var updatedTask = newSettings.tasks[index]
        mutate(&updatedTask)
        newSettings.tasks[index] = updatedTask
        store.saveSettings(newSettings)
    }

    private func removeTask(_ task: Task) {
        var newSettings = store.settings
        newSettings.tasks.removeAll { $0.id == task.id }
        store.saveSettings(newSettings)
    }
}
