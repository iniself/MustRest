import SwiftUI
import AppKit
import MustRest

struct SettingsView: View {
    @EnvironmentObject var engine: PomodoroEngine
    @EnvironmentObject var store: PomodoroStore
    @EnvironmentObject var windowManager: WindowManager

    /// Local drafts for the settings UI. Edits only mutate these drafts;
    /// the values are written to the store (and thus persisted) when the user
    /// explicitly taps "保存并关闭". Closing the window via Esc / close button
    /// discards the drafts, keeping the previously saved settings untouched.
    @State private var draftTasks: [Task] = Task.defaultTasks()
    @State private var draftIsOverlayBlocking: Bool = true
    @State private var showingResetAlert = false

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
                            Toggle(draftIsOverlayBlocking ? "遮罩全屏" : "允许退出", isOn: Binding(
                                get: { draftIsOverlayBlocking },
                                set: { draftIsOverlayBlocking = $0 }
                            ))
                        }
                        .formStyle(.grouped)
                    }

                    // Section 2: Task Management
                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务列表")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        VStack(spacing: 12) {
                            ForEach(draftTasks) { task in
                                TaskRowView(
                                    task: task,
                                    onTaskChange: { updatedTask in
                                        updateDraftTask(updatedTask)
                                    },
                                    onRemove: {
                                        removeDraftTask(task)
                                    }
                                )
                            }

                            if draftTasks.isEmpty {
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

                        // "+" button centered below the task list.
                        HStack {
                            Spacer()
                            Button(action: addTask) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        // Reset button below the task list: restores the
                        // default task set after the confirmation alert.
                        HStack {
                            Spacer()
                            Button(action: { showingResetAlert = true }) {
                                Label("恢复默认任务", systemImage: "arrow.counterclockwise")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            Divider()
            HStack {
                Spacer()
                Button(action: {
                    saveDraft()
                    windowManager.closeSettings()
                }) {
                    // Add internal padding so the button grows without
                    // changing the label text size.
                    Text("保存并关闭")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
        .alert("恢复默认任务", isPresented: $showingResetAlert) {
            Button("取消", systemImage: "xmark.circle.fill", role: .cancel) {}
            Button("恢复默认", systemImage: "arrow.counterclockwise", role: .destructive) {
                resetToDefaultTasks()
            }
        } message: {
            Text("这会清空并删除你所有的自定义任务，并恢复为默认的三个任务，此操作无法撤销。")
        }
        .onAppear {
            // Seed the drafts from the last saved settings whenever the window
            // is presented, so discarded edits never leak into the next session.
            draftTasks = store.settings.tasks
            draftIsOverlayBlocking = store.settings.isOverlayBlocking
        }
    }

    /// Commits the local drafts into the persisted store.
    private func saveDraft() {
        var newSettings = store.settings
        newSettings.tasks = draftTasks
        newSettings.isOverlayBlocking = draftIsOverlayBlocking
        store.saveSettings(newSettings)
    }

    private func addTask() {
        let newTask = Task(name: "新任务", workIntervalSeconds: 15 * 60, breakDurationSeconds: 15)
        draftTasks.append(newTask)
        // The newly added task becomes the one the menu bar toggle runs next.
        engine.setCurrentTask(newTask)
    }

    private func removeDraftTask(_ task: Task) {
        draftTasks.removeAll { $0.id == task.id }
    }

    private func updateDraftTask(_ task: Task) {
        guard let index = draftTasks.firstIndex(where: { $0.id == task.id }) else { return }
        draftTasks[index] = task
    }

    /// Restores the default task set and persists it. Called from the
    /// destructive action of the reset confirmation alert.
    private func resetToDefaultTasks() {
        var newSettings = store.settings
        newSettings.tasks = Task.defaultTasks()
        store.saveSettings(newSettings)
        // Reflect the reset immediately in the open window drafts.
        draftTasks = Task.defaultTasks()
        // Point the engine back at the first default task after the reset.
        engine.setCurrentTask(Task.defaultTasks()[0])
    }
}

struct TaskRowView: View {
    let task: Task
    var onTaskChange: (Task) -> Void
    var onRemove: () -> Void

    // Local draft state backing the text fields so that every keystroke is
    // reflected immediately and the field keeps its first responder status.
    @State private var nameText: String
    @State private var workMinutes: Double
    @State private var breakSeconds: Double

    init(task: Task, onTaskChange: @escaping (Task) -> Void, onRemove: @escaping () -> Void) {
        self.task = task
        self.onTaskChange = onTaskChange
        self.onRemove = onRemove
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

                Button(action: onRemove) {
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

            // Overlay background color picker; falls back to the default color.
            ColorPicker("遮罩背景色", selection: overlayColor)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
    }

    // Text fields read from / write to local draft state, then propagate the
    // change up to the settings view's drafts. The store is only touched when
    // the user explicitly saves.
    private var nameBinding: Binding<String> {
        Binding(
            get: { nameText },
            set: { newValue in
                nameText = newValue
                var updatedTask = task
                updatedTask.name = newValue
                onTaskChange(updatedTask)
            }
        )
    }

    private var workBinding: Binding<Double> {
        Binding(
            get: { workMinutes },
            set: { newValue in
                workMinutes = newValue
                var updatedTask = task
                updatedTask.workIntervalSeconds = newValue * 60
                onTaskChange(updatedTask)
            }
        )
    }

    private var breakBinding: Binding<Double> {
        Binding(
            get: { breakSeconds },
            set: { newValue in
                breakSeconds = newValue
                var updatedTask = task
                updatedTask.breakDurationSeconds = newValue
                onTaskChange(updatedTask)
            }
        )
    }

    /// Binding for the task's overlay background color.
    private var overlayColor: Binding<Color> {
        Binding(
            get: { Self.color(fromHex: task.overlayBackgroundColor ?? "#ffb3a7") },
            set: { newValue in
                var updatedTask = task
                updatedTask.overlayBackgroundColor = Self.hexString(from: newValue)
                onTaskChange(updatedTask)
            }
        )
    }

    private static func color(fromHex hex: String) -> Color {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        if clean.count != 6 { return Color(red: 1.0, green: 0.698, blue: 0.655) }
        let value = Int(clean, radix: 16) ?? 0
        let r = (value >> 16) & 0xff
        let g = (value >> 8) & 0xff
        let b = value & 0xff
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private static func hexString(from color: Color) -> String {
        guard let components = color.cgColor?.components else { return "#ffb3a7" }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}
