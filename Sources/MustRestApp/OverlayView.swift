import SwiftUI
import MustRest

struct OverlayView: View {
    @ObservedObject var engine: PomodoroEngine
    @EnvironmentObject var store: PomodoroStore

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.698, blue: 0.655)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("休息时间")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if let task = engine.currentTask {
                    Text("当前任务：\(task.name)")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.9))
                } else {
                    Text("休息一下吧")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.9))
                }

                Text(formatTime(engine.remainingSeconds))
                    .font(.system(size: 120, design: .monospaced))
                    .fontWeight(.black)
                    .foregroundColor(.white)
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}
