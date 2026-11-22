import Foundation
import AppKit

public final class PomodoroEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case working
        case paused
        case breaking
    }

    /// A single pomodoro run belonging to one task. Each task owns one run,
    /// so several tasks can rest / work at the same time.
    public struct TaskRun: Equatable {
        public let task: Task
        public var phase: Phase = .idle
        public var endDate: Date? = nil
        public var remainingAtPause: TimeInterval = 0
        public var pausedFrom: Phase? = nil

        public init(task: Task) {
            self.task = task
        }
    }

    /// All task runs keyed by task id, so parallel tasks each count down
    /// independently of each other.
    public private(set) var runs: [UUID: TaskRun] = [:]

    /// The task whose run the overlay / toggle currently cares about.
    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var currentTask: Task?
    @Published public private(set) var remainingSeconds: TimeInterval = 0

    private let clock: PomodoroClock
    private var timer: Timer?
    /// Plays the overlay end reminder sound for the given sound name (a macOS
    /// system sound name or a custom sound file name); defaults to the system
    /// sounds and falls back to the custom file in the app support directory.
    /// Injectable for tests.
    private let playOverlayEndSound: (String) -> Void

    public init(clock: PomodoroClock = SystemPomodoroClock(), playOverlayEndSound: @escaping (String) -> Void = { name in
        if let sound = NSSound(named: name) {
            sound.play()
            return
        }
        let customURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/MustRest/Sounds/" + name)
        if FileManager.default.fileExists(atPath: customURL.path), let sound = NSSound(contentsOfFile: customURL.path, byReference: false) {
            sound.play()
        }
    }) {
        self.clock = clock
        self.playOverlayEndSound = playOverlayEndSound
    }

    public var isPaused: Bool {
        phase == .paused
    }

    /// Whether the overlay end reminder sound should play at all. Reads the
    /// shared store so the settings toggle applies without restarting.
    public var isOverlayEndSoundEnabled: Bool {
        PomodoroStore.shared.settings.isOverlaySoundEnabled
    }

    /// The user-selected overlay end sound; nil falls back to the default
    /// system "Hero" sound.
    public var overlayEndSoundName: String? {
        PomodoroStore.shared.settings.overlaySoundName
    }

    /// Runs a fresh pomodoro run (work -> break cycle) for the given task.
    public func start(task: Task) {
        var run = TaskRun(task: task)
        run.phase = .working
        run.endDate = clock.now().addingTimeInterval(task.workIntervalSeconds)
        run.remainingAtPause = task.workIntervalSeconds
        runs[task.id] = run
        currentTask = task
        phase = .working
        remainingSeconds = task.workIntervalSeconds
        scheduleTimer()
        notifyChange()
    }

    /// Runs a fresh pomodoro run for every task so all of them count down
    /// in parallel from now.
    public func startAll(tasks: [Task]) {
        guard !tasks.isEmpty else { return }
        for task in tasks {
            var run = TaskRun(task: task)
            run.phase = .working
            run.endDate = clock.now().addingTimeInterval(task.workIntervalSeconds)
            run.remainingAtPause = task.workIntervalSeconds
            runs[task.id] = run
        }
        currentTask = tasks[0]
        phase = .working
        remainingSeconds = tasks[0].workIntervalSeconds
        scheduleTimer()
        notifyChange()
    }

    /// Pauses every running task run so parallel rests stay in sync.
    public func pause() {
        guard phase == .working || phase == .breaking else { return }
        for (id, run) in runs {
            guard run.phase == .working || run.phase == .breaking else { continue }
            var updatedRun = run
            updatedRun.phase = .paused
            updatedRun.pausedFrom = run.phase
            updatedRun.endDate = nil
            updatedRun.remainingAtPause = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
            runs[id] = updatedRun
        }
        guard let taskId = currentTask?.id, runs[taskId]?.phase == .paused else { return }
        phase = .paused
        remainingSeconds = max(0, runs[taskId]?.remainingAtPause ?? 0)
        invalidateTimer()
        notifyChange()
    }

    /// Resumes every paused task run.
    public func resume() {
        guard phase == .paused else { return }
        var didResume = false
        for (id, run) in runs where run.phase == .paused {
            guard let pausedPhase = run.pausedFrom else { continue }
            var updatedRun = run
            updatedRun.phase = pausedPhase
            updatedRun.pausedFrom = nil
            updatedRun.endDate = clock.now().addingTimeInterval(updatedRun.remainingAtPause)
            runs[id] = updatedRun
            didResume = true
        }
        guard didResume, let taskId = currentTask?.id, let run = runs[taskId] else { return }
        phase = run.phase == .paused ? .working : run.phase
        remainingSeconds = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
        scheduleTimer()
        notifyChange()
    }

    /// Advances every task run so parallel tasks each count down independently.
    public func tick(now: Date) {
        var didChangePhase = false

        // Work -> break transitions for all running tasks.
        let workingIds = runs.keys.filter { runs[$0]?.phase == .working }.sorted()
        for id in workingIds {
            guard var run = runs[id] else { continue }
            let remaining = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
            if remaining > 0 { continue }
            let task = run.task
            run.phase = .breaking
            run.endDate = now.addingTimeInterval(task.breakDurationSeconds)
            runs[id] = run
            // The task that just entered its break becomes the featured task
            // so the overlay shows that task's countdown.
            currentTask = task
            phase = .breaking
            remainingSeconds = task.breakDurationSeconds
            didChangePhase = true
        }

        // Break -> work transitions for all resting tasks.
        let breakingIds = runs.keys.filter { runs[$0]?.phase == .breaking }.sorted()
        for id in breakingIds {
            guard var run = runs[id] else { continue }
            let remaining = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
            if remaining > 0 { continue }
            let task = run.task
            run.phase = .working
            run.endDate = now.addingTimeInterval(task.workIntervalSeconds)
            run.remainingAtPause = task.workIntervalSeconds
            runs[id] = run
            currentTask = task
            phase = .working
            remainingSeconds = task.workIntervalSeconds
            didChangePhase = true

            // The overlay that displayed this break has just ended on its own
            // (the countdown reached zero). Remind the user that they may
            // continue with the computer via the system sound. When another
            // task break is still pending the overlay overlap is resolved by
            // the later end, so the reminder waits for that final one.
            let resolvedOverlayEndSoundName: String? = overlayEndSoundName ?? "Hero"
            if isOverlayEndSoundEnabled, !hasPendingBreaks, let soundName = resolvedOverlayEndSoundName {
                playOverlayEndSound(soundName)
            }
        }

        // Keep the featured run's countdown in sync while it is working or in
        // its break, so the overlay animates every second.
        if phase == .working || phase == .breaking,
           let taskId = currentTask?.id,
           let run = runs[taskId],
           run.phase == phase {
            let remaining = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
            if remaining != remainingSeconds {
                remainingSeconds = remaining
            }
        }

        // With parallel tasks more than one break can be pending at the same
        // time. A newly started break may take over the overlay, but once such
        // a break ends the overlay has to fall back to the break that is still
        // running instead of simply disappearing.
        if phase == .working || phase == .breaking {
            let pendingBreaks = runs.values
                .filter { run in
                    run.phase == .breaking && (run.endDate?.timeIntervalSinceNow ?? 0) > 0
                }
                .sorted { lhs, rhs in
                    (lhs.endDate?.timeIntervalSinceNow ?? 0) < (rhs.endDate?.timeIntervalSinceNow ?? 0)
                }
            if let pendingBreak = pendingBreaks.first,
               currentTask?.id != pendingBreak.task.id || phase != .breaking {
                currentTask = pendingBreak.task
                phase = .breaking
                remainingSeconds = max(0, pendingBreak.endDate?.timeIntervalSinceNow ?? 0)
                notifyChange()
            }
        }

        if didChangePhase {
            notifyChange()
        }
    }

    /// Clears every task run and returns the engine to the idle state.
    /// Called when the task set is replaced, e.g. via the settings reset.
    public func reset() {
        runs = [:]
        phase = .idle
        remainingSeconds = 0
        currentTask = nil
        invalidateTimer()
        notifyChange()
    }

    /// Sets the task that the toggle action should control next without
    /// starting the timer. Used when the user adds / edits tasks in settings.
    public func setCurrentTask(_ task: Task) {
        currentTask = task
        guard let run = runs[task.id] else { return }
        phase = run.phase
        remainingSeconds = Self.remainingSeconds(for: run)
    }

    /// Ends the current task run early, e.g. through the overlay exit button
    /// when early exit is allowed. The next start begins a fresh run.
    public func endCurrentRun() {
        guard let taskId = currentTask?.id else { return }
        runs[taskId] = nil
        phase = .idle
        remainingSeconds = 0
        notifyChange()
    }

    /// Updates the task data of an existing run (e.g. after the user changed
    /// task durations / colors in the settings) so countdowns and breaks pick
    /// up the new values without restarting the engine.
    public func updateTask(_ task: Task) {
        guard let run = runs[task.id] else { return }
        var updatedRun = TaskRun(task: task)
        updatedRun.phase = run.phase
        updatedRun.endDate = run.endDate
        updatedRun.remainingAtPause = run.remainingAtPause
        updatedRun.pausedFrom = run.pausedFrom
        runs[task.id] = updatedRun
        if currentTask?.id == task.id {
            currentTask = task
        }
    }

    private func scheduleTimer() {
        invalidateTimer()
        // Capture the engine strongly: the engine is owned by the app for its
        // whole lifetime (StateObject), so the repeating timer -> closure ->
        // engine cycle is not a practical leak here. Avoiding the `[weak self]`
        // load also removes the swift_weakLoadStrong crash path seen in crash
        // reports ("Program crashed: Bad pointer dereference" inside the timer
        // callback).
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            self.tick(now: Date())
        }
        self.timer = timer
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func notifyChange() {
        remainingSeconds = max(0, remainingSeconds)
        NotificationCenter.default.post(name: NSNotification.Name("PomodoroPhaseChanged"), object: self)
    }

    /// True while another task run is still breaking, i.e. while the overlay
    /// that just ended was overlapped by a still running break.
    private var hasPendingBreaks: Bool {
        runs.values.contains { run in
            run.phase == .breaking && (run.endDate?.timeIntervalSinceNow ?? 0) > 0
        }
    }

    private static func remainingSeconds(for run: TaskRun) -> TimeInterval {
        switch run.phase {
        case .working, .breaking:
            return max(0, run.endDate?.timeIntervalSinceNow ?? 0)
        case .paused:
            return run.remainingAtPause
        case .idle:
            return 0
        }
    }
}
