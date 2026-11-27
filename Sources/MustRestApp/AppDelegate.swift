import AppKit

/// Blocks app termination while the blocking overlay is on screen so the user
/// cannot skip a break with Command + Q or the menu item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if WindowManager.active?.isBlockingOverlay == true {
            return .terminateCancel
        }
        return .terminateNow
    }
}
