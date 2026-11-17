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

            // Early exit button, only available when the user allowed quitting
            // early (switch OFF / "allow exit").
            if !store.settings.isOverlayBlocking {
                VStack {
                    Spacer()
                    Button("退出") {
                        engine.endCurrentRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 40)
                    .foregroundColor(.white)
                }
            }
        }
    }

    /// The overlay background color: the current task's custom color, or the
    /// default color when the task has none.
    private var overlayBackgroundColor: Color {
        if let hex = engine.currentTask?.overlayBackgroundColor, !hex.isEmpty {
            return Self.color(fromHex: hex)
        }
        return Self.color(fromHex: "#ffb3a7")
    }

    private static func color(fromHex hex: String) -> Color {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        if clean.count != 6 { return Color(red: 1.0, green: 0.698, blue: 0.655) }
        let value = Int(clean, radix: 16) ?? 0
        let r = (value >> 16) & 0xff
        let g = (value >> 8) & 0xff
        let b = value & 0xff
        return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, sec)
    }
}
