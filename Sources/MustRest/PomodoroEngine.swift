import Foundation

public final class PomodoroEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case working
        case paused
        case breaking
    }

    /// A single pomodoro run belonging to one task. Each task owns one run,
    /// so several tasks can be resting / working at the same time.
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

    /// The task whose run the menu bar toggle is currently controlling.
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

    /// Runs a task: starts a fresh pomodoro run (work -> break cycle) for it.
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

    /// Pauses the run of the task controlled by the menu bar toggle.
    public func pause() {
        guard phase == .working || phase == .breaking else { return }
        guard let taskId = currentTask?.id, var run = runs[taskId] else { return }
        let fromPhase = run.phase
        run.phase = .paused
        run.pausedFrom = fromPhase
        run.endDate = nil
        run.remainingAtPause = max(0, remainingSeconds)
        runs[taskId] = run
        phase = .paused
        remainingSeconds = run.remainingAtPause
        invalidateTimer()
        notifyChange()
    }

    /// Resumes the run of the task controlled by the menu bar toggle.
    public func resume() {
        guard phase == .paused, let taskId = currentTask?.id, var run = runs[taskId], let pausedPhase = run.pausedFrom else { return }
        run.phase = pausedPhase
        run.pausedFrom = nil
        run.endDate = clock.now().addingTimeInterval(run.remainingAtPause)
        runs[taskId] = run
        phase = pausedPhase
        remainingSeconds = max(0, run.endDate?.timeIntervalSinceNow ?? 0)
        scheduleTimer();
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
            if currentTask?.id == id {
                phase = .breaking
                remainingSeconds = task.breakDurationSeconds
                didChangePhase = true
            }
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
            if currentTask?.id == id {
                phase = .working
                remainingSeconds = task.workIntervalSeconds
                didChangePhase = true
            }
        }

        if didChangePhase {
            notifyChange()
        }
    }

    /// Sets the task that the toggle action should control next.
    public func setCurrentTask(_ task: Task) {
        currentTask = task
        guard let run = runs[task.id] else { return }
        phase = run.phase
        remainingSeconds = Self.remainingSeconds(for: run)
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
