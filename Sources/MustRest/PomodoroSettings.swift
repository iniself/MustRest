import Foundation

public struct PomodoroSettings: Codable {
    /// When true the overlay is full screen and the user must wait for the
    /// timer to finish (early exit is not allowed). When false the user may
    /// exit the current run early through the overlay exit button.
    public var isOverlayBlocking: Bool
    public var tasks: [Task]
    /// When true the app registers itself as a login item and therefore
    /// launches automatically at computer boot; the launch then triggers the
    /// automatic pomodoro start (see MustRestApp).
    public var autoLaunchEnabled: Bool

    public init(tasks: [Task] = Task.defaultTasks(), isOverlayBlocking: Bool = true, autoLaunchEnabled: Bool = false) {
        self.tasks = tasks
        self.isOverlayBlocking = isOverlayBlocking
        self.autoLaunchEnabled = autoLaunchEnabled
    }
}

public final class PomodoroStore: ObservableObject {
    public static let shared = PomodoroStore()

    @Published public var settings: PomodoroSettings

    private let defaults: UserDefaults

    private enum Keys {
        static let tasks = "mustrest.tasks"
        static let isOverlayBlocking = "mustrest.isOverlayBlocking"
        static let autoLaunchEnabled = "mustrest.autoLaunchEnabled"
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
        // Defaults to off (the app does not launch at boot) when the key is
        // missing.
        let autoLaunchEnabled = defaults.object(forKey: Keys.autoLaunchEnabled) == nil
            ? false
            : defaults.bool(forKey: Keys.autoLaunchEnabled)
        self.settings = PomodoroSettings(
            tasks: tasks,
            isOverlayBlocking: isOverlayBlocking,
            autoLaunchEnabled: autoLaunchEnabled
        )
    }

    public func saveSettings(_ newSettings: PomodoroSettings) {
        let data = (try? JSONEncoder().encode(newSettings.tasks)) ?? Data()
        defaults.set(data, forKey: Keys.tasks)
        defaults.set(newSettings.isOverlayBlocking, forKey: Keys.isOverlayBlocking)
        defaults.set(newSettings.autoLaunchEnabled, forKey: Keys.autoLaunchEnabled)
        self.settings = newSettings
    }
}
