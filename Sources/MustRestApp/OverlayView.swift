import SwiftUI
import Foundation
import MustRest

struct OverlayView: View {
    @ObservedObject var engine: PomodoroEngine
    @EnvironmentObject var store: PomodoroStore

    var body: some View {
        ZStack {
            overlayBackgroundColor
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

            // While manual exit is allowed, the overlay shows the Escape hint.
            // The blocking overlay has no exit at all, so it shows nothing.
            if !store.settings.isOverlayBlocking {
                VStack {
                    Spacer()
                    Text("长按 Esc 3 秒可退出")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.bottom, 28)
                }
            }
        }
    }

    /// The overlay background color: the current task's custom color, or the
    /// default color when the task has none.
    private var overlayBackgroundColor: Color {
        let task = engine.currentTask.flatMap { task in
            store.settings.tasks.first { $0.id == task.id } ?? task
        }
        if let hex = task?.overlayBackgroundColor, !hex.isEmpty {
            return Self.color(fromHex: hex)
        }
        return Self.color(fromHex: "#B98278")
    }

    private static func color(fromHex hex: String) -> Color {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        if clean.count != 6 { return Self.color(fromHex: "#B98278") }
        let value = Int(clean, radix: 16) ?? 0
        let r = (value >> 16) & 0xff
        let g = (value >> 8) & 0xff
        let b = value & 0xff
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        // Counts under a minute are shown as plain seconds (e.g. a 15s eye
        // break); longer counts are shown as minutes:seconds (e.g. a 10min
        // standing break) with the countdown still ticking.
        if totalSeconds < 60 {
            return "\(totalSeconds)"
        }
        let minutes = totalSeconds / 60
        let sec = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}
