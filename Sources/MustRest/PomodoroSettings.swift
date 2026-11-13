import Foundation

public enum ReminderMethod: String, Codable, CaseIterable {
    case overlay = "overlay"
    case banner = "banner"

    public var displayName: String {
        switch self {
        case .overlay:
            return "遮罩全屏"
        case .banner:
            return "通知提醒"
        }
    }
}

public struct PomodoroSettings: Codable {
    public var tasks: [Task]
    public var reminderMethod: ReminderMethod

    public init(tasks: [Task] = Task.defaultTasks(), reminderMethod: ReminderMethod = .overlay) {
        self.tasks = tasks
        self.reminderMethod = reminderMethod
    }
}

public final class PomodoroStore: ObservableObject {
    public static let shared = PomodoroStore()

    @Published public var settings: PomodoroSettings

    private let defaults: UserDefaults

    private enum Keys {
        static let tasks = "mustrest.tasks"
        static let reminderMethod = "mustrest.reminderMethod"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        var tasks: [Task] = Task.defaultTasks()
        if let data = defaults.data(forKey: Keys.tasks),
           let decodedTasks = try? JSONDecoder().decode([Task].self, from: data),
           !decodedTasks.isEmpty {
            tasks = decodedTasks
        }

        let method: ReminderMethod = defaults.string(forKey: Keys.reminderMethod).flatMap { ReminderMethod(rawValue: $0) } ?? .overlay
        self.settings = PomodoroSettings(tasks: tasks, reminderMethod: method)
    }

    public func saveSettings(_ newSettings: PomodoroSettings) {
        let data = (try? JSONEncoder().encode(newSettings.tasks)) ?? Data()
        defaults.set(data, forKey: Keys.tasks)
        defaults.set(newSettings.reminderMethod.rawValue, forKey: Keys.reminderMethod)
        self.settings = newSettings
    }
}