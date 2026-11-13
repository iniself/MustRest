import Foundation

/// Abstraction over the clock used by the pomodoro engine, mainly to make the
/// engine deterministic in unit tests.
public protocol PomodoroClock {
    func now() -> Date
}

public struct SystemPomodoroClock: PomodoroClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public struct FixedPomodoroClock: PomodoroClock {
    private let date: Date

    public init(now: Date = Date()) {
        date = now
    }

    public func now() -> Date {
        date
    }
}
