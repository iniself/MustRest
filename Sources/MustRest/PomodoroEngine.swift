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
            remainingSeconds = remaining
        }
    }

    private func scheduleTimer() {
        invalidateTimer()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
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
