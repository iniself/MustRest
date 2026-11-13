import XCTest
import MustRest

final class TaskTests: XCTestCase {
    func testDefaultTasksContainExpectedBreakTypes() {
        let tasks = Task.defaultTasks()
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].name, "休息眼睛")
        XCTAssertEqual(tasks[0].workIntervalSeconds, 15 * 60)
        XCTAssertEqual(tasks[0].breakDurationSeconds, 15)
        XCTAssertEqual(tasks[1].name, "站立运动")
        XCTAssertEqual(tasks[1].workIntervalSeconds, 60 * 60)
        XCTAssertEqual(tasks[1].breakDurationSeconds, 5 * 60)
        XCTAssertEqual(tasks[2].name, "长时站立")
        XCTAssertEqual(tasks[2].workIntervalSeconds, 120 * 60)
        XCTAssertEqual(tasks[2].breakDurationSeconds, 10 * 60)
    }
}
