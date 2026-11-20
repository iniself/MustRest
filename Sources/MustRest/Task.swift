import Foundation

/// A single pomodoro task.
///
/// The user accumulates work time during `workIntervalSeconds`, after which
/// a break of `breakDurationSeconds` is suggested.
public struct Task: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var workIntervalSeconds: TimeInterval
    public var breakDurationSeconds: TimeInterval
    /// Overlay background color as a hex string (e.g. "#B98278").
    /// `nil` means the task uses the default overlay color.
    public var overlayBackgroundColor: String? = nil

    public init(id: UUID = UUID(), name: String, workIntervalSeconds: TimeInterval, breakDurationSeconds: TimeInterval) {
        self.id = id
        self.name = name
        self.workIntervalSeconds = max(1, workIntervalSeconds)
        self.breakDurationSeconds = max(1, breakDurationSeconds)
        self.overlayBackgroundColor = nil
    }

    /// Short eye break: work 20 minutes, then 15 seconds of rest.
    public static let eyeRest = Task(name: "休息眼睛", workIntervalSeconds: 20 * 60, breakDurationSeconds: 15)

    /// Standing break: work 1 hour, then 5 minutes of standing.
    public static let standing = Task(name: "起身走走", workIntervalSeconds: 60 * 60, breakDurationSeconds: 5 * 60)

    /// Long standing break: work 2 hours, then 10 minutes of standing.
    public static let longStanding = Task(name: "锻炼身体", workIntervalSeconds: 120 * 60, breakDurationSeconds: 10 * 60)

    /// The default set of tasks shipped with the app.
    public static func defaultTasks() -> [Task] {
        [eyeRest, standing, longStanding]
    }
}
