import XCTest
import MustRest

final class PomodoroEngineTests: XCTestCase {
    private var engine: PomodoroEngine!
    private var clock: FixedPomodoroClock!

    override func setUp() {
        super.setUp()
        clock = FixedPomodoroClock()
        engine = PomodoroEngine(clock: clock)
    }

    override func tearDown() {
        engine = nil
        clock = nil
        super.tearDown()
    }

    func testWorkPhaseStartsWithTaskInterval() {
        let task = Task(name: "休息眼睛", workIntervalSeconds: 15 * 60, breakDurationSeconds: 15)
        engine.start(task: task)
        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.currentTask?.id, task.id)
        XCTAssertEqual(engine.remainingSeconds, 15 * 60, accuracy: 0.001)
    }

    func testBreakStartsWhenWorkIntervalElapses() {
        let task = Task(name: "休息眼睛", workIntervalSeconds: 10, breakDurationSeconds: 5)
        engine.start(task: task)
        engine.tick(now: clock.now().addingTimeInterval(9))
        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 1, accuracy: 0.001)
        engine.tick(now: clock.now().addingTimeInterval(10))
        XCTAssertEqual(engine.phase, .breaking)
        XCTAssertEqual(engine.remainingSeconds, 5, accuracy: 0.001)
    }

    func testBreakCompletionStartsNextWorkCycle() {
        let task = Task(name: "站立运动", workIntervalSeconds: 10, breakDurationSeconds: 5)
        engine.start(task: task)
        engine.tick(now: clock.now().addingTimeInterval(10))
        engine.tick(now: clock.now().addingTimeInterval(15))
        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 10, accuracy: 0.001)
    }

    func testPauseDuringWorkPreservesRemainingTime() {
        let task = Task(name: "休息眼睛", workIntervalSeconds: 10, breakDurationSeconds: 5)
        engine.start(task: task)
        engine.pause()
        XCTAssertEqual(engine.phase, .paused)
        XCTAssertEqual(engine.remainingSeconds, 10, accuracy: 0.001)
        engine.resume()
        XCTAssertEqual(engine.phase, .working)
        XCTAssertEqual(engine.remainingSeconds, 10, accuracy: 0.001)
    }

    func testOverlayWarningScheduledBeforeUpcomingBreakOverlay() {
        var scheduledFireDate: Date?
        var scheduledTitle: String?
        var scheduledMessage: String?
        var didCancel = false
        let warningEngine = PomodoroEngine(
            clock: clock,
            playOverlayEndSound: { _ in },
            scheduleOverlayWarning: { fireDate, title, message in
                scheduledFireDate = fireDate
                scheduledTitle = title
                scheduledMessage = message
            },
            cancelOverlayWarning: { didCancel = true }
        )

        let task = Task(name: "休息眼睛", workIntervalSeconds: 10, breakDurationSeconds: 5)
        warningEngine.start(task: task)
        // The upcoming break overlay appears when the work interval ends, so
        // the user has to be warned ten seconds before that overlay shows up.
        XCTAssertNotNil(scheduledFireDate)
        XCTAssertEqual(scheduledFireDate!.timeIntervalSinceNow, clock.now().timeIntervalSinceNow, accuracy: 0.001)
        XCTAssertEqual(scheduledTitle, "该休息了！")
        XCTAssertEqual(scheduledMessage, "【\(task.name)】将在10秒内开始")
        XCTAssertFalse(didCancel)

        warningEngine.pause()
        XCTAssertTrue(didCancel)
    }

    func testOverlayWarningCancelledWhenBreakStarts() {
        var didCancel = false
        let warningEngine = PomodoroEngine(
            clock: clock,
            playOverlayEndSound: { _ in },
            scheduleOverlayWarning: { _ in },
            cancelOverlayWarning: { didCancel = true }
        )
        let task = Task(name: "休息眼睛", workIntervalSeconds: 10, breakDurationSeconds: 5)
        warningEngine.start(task: task)
        warningEngine.tick(now: clock.now().addingTimeInterval(10))
        XCTAssertEqual(warningEngine.phase, .breaking)
        XCTAssertTrue(didCancel)
    }

    func testCancelPendingOverlayWarningCancelsScheduledWarning() {
        var cancelCount = 0
        let warningEngine = PomodoroEngine(
            clock: clock,
            playOverlayEndSound: { _ in },
            scheduleOverlayWarning: { _, _, _ in },
            cancelOverlayWarning: { cancelCount += 1 }
        )
        warningEngine.cancelPendingOverlayWarning()
        XCTAssertEqual(cancelCount, 1)
    }
}
