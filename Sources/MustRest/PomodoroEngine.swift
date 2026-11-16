import Foundation

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

    public init(clock: PomodoroClock = SystemPomodoroClock()) {
        self.clock = clock
    }

    public var isPaused: Bool {
        phase == .paused
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

        if didChangePhase {
            notifyChange()
        }
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
