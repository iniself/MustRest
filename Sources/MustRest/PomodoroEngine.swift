import Foundation

public final class PomodoroEngine: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case working
        case paused
        case breaking
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var currentTask: Task?
    @Published public private(set) var remainingSeconds: TimeInterval = 0

    private let clock: PomodoroClock
    private var task: Task?
    private var pausedFrom: Phase?
    private var endDate: Date?
    private var remainingAtPause: TimeInterval = 0
    private var timer: Timer?

    public init(clock: PomodoroClock = SystemPomodoroClock()) {
        self.clock = clock
    }

    public var isPaused: Bool {
        phase == .paused
    }

    public func start(task: Task) {
        self.task = task
        currentTask = task
        phase = .working
        pausedFrom = nil
        endDate = clock.now().addingTimeInterval(task.workIntervalSeconds)
        remainingAtPause = task.workIntervalSeconds
        remainingSeconds = task.workIntervalSeconds
        scheduleTimer()
        notifyChange()
    }

    public func pause() {
        guard phase == .working || phase == .breaking else { return }
        pausedFrom = phase
        phase = .paused
        endDate = nil
        remainingAtPause = max(0, remainingSeconds)
        invalidateTimer()
        notifyChange()
    }

    public func resume() {
        guard phase == .paused, let pausedPhase = pausedFrom else { return }
        phase = pausedPhase
        pausedFrom = nil
        endDate = clock.now().addingTimeInterval(remainingAtPause)
        scheduleTimer()
        notifyChange()
    }

    /// Sets the task that the toggle action should run next without
    /// starting the timer. Used when the user adds / edits tasks in settings.
    public func setCurrentTask(_ task: Task) {
        self.task = task
        currentTask = task
    }

    /// Advances the engine by the real elapsed time.
    public func tick(now: Date) {
        guard phase == .working || phase == .breaking else { return }
        let remaining = max(0, endDate?.timeIntervalSinceNow ?? 0)
        if phase == .working, remaining <= 0 {
            phase = .breaking
            endDate = now.addingTimeInterval(task?.breakDurationSeconds ?? 0)
            remainingSeconds = max(0, endDate?.timeIntervalSinceNow ?? 0)
            notifyChange()
        } else if phase == .breaking, remaining <= 0 {
            phase = .working
            endDate = now.addingTimeInterval(task?.workIntervalSeconds ?? 0)
            remainingSeconds = max(0, endDate?.timeIntervalSinceNow ?? 0)
            notifyChange()
        } else {
            // Only publish when the value actually changed; assigning an
            // equal value still fires @Published and triggers SwiftUI updates
            // on every timer tick.
            if remaining != remainingSeconds {
                remainingSeconds = remaining
            }
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
}
