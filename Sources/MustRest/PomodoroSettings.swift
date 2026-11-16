import Foundation

public struct PomodoroSettings: Codable {
    /// When true the overlay is full screen and the user must wait for the
    /// timer to finish (early exit is not allowed). When false the user may
    /// exit the current run early through the overlay exit button.
    public var isOverlayBlocking: Bool
    public var tasks: [Task]

    public init(tasks: [Task] = Task.defaultTasks(), isOverlayBlocking: Bool = true) {
        self.tasks = tasks
        self.isOverlayBlocking = isOverlayBlocking
    }
}

public final class PomodoroStore: ObservableObject {
    public static let shared = PomodoroStore()

    @Published public var settings: PomodoroSettings

    private let defaults: UserDefaults

    private enum Keys {
        static let tasks = "mustrest.tasks"
        static let isOverlayBlocking = "mustrest.isOverlayBlocking"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var tasks: [Task] = Task.defaultTasks()
        if let data = defaults.data(forKey: Keys.tasks),
           let decodedTasks = try? JSONDecoder().decode([Task].self, from: data),
           !decodedTasks.isEmpty {
            tasks = decodedTasks
        }

        // Defaults to blocking (full screen overlay) when the key is missing.
        let isOverlayBlocking = defaults.object(forKey: Keys.isOverlayBlocking) == nil
            ? true
            : defaults.bool(forKey: Keys.isOverlayBlocking)
        self.settings = PomodoroSettings(tasks: tasks, isOverlayBlocking: isOverlayBlocking)
    }

    public func saveSettings(_ newSettings: PomodoroSettings) {
        let data = (try? JSONEncoder().encode(newSettings.tasks)) ?? Data()
        defaults.set(data, forKey: Keys.tasks)
        defaults.set(newSettings.isOverlayBlocking, forKey: Keys.isOverlayBlocking)
        self.settings = newSettings
    }
}
