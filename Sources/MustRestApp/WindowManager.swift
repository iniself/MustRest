import SwiftUI
import AppKit
import ServiceManagement
import MustRest

class WindowManager: ObservableObject {
    private var settingsWindow: NSWindow?
    /// One overlay window per display, keyed by display ID, so every screen is
    /// covered instead of only the main one.
    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var phaseObserver: NSObjectProtocol?
    private var colorPanelObserver: NSObjectProtocol?
    private var colorPanelTimer: Timer?
    private var lastColorPanelVisible = false
    private var keyMonitor: Any?

    init() {
        // A menu bar only app must run with an accessory activation policy,
        // otherwise it shows up in the Dock and the Command + Tab switcher.
        NSApp.setActivationPolicy(.accessory)
        setupPhaseObserver()
        setupColorPanelObserver()
        setupKeyMonitor()
    }

    private func setupKeyMonitor() {
        // Allow the Escape key to close the settings window.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closeSettings()
                return nil
            }
            return event
        }
    }

    private func setupPhaseObserver() {
        phaseObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PomodoroPhaseChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let engine = notification.object as? PomodoroEngine else { return }
            if engine.phase == .breaking {
                self.showOverlay(engine: engine, store: PomodoroStore.shared)
            } else if !engine.isPaused {
                self.hideOverlay()
            }
        }
    }

    private func setupColorPanelObserver() {
        // SwiftUI ColorPicker opens a color panel when the user picks a color;
        // watch it becoming visible so we can place it next to the settings
        // window instead of letting the system choose a position. Observing
        // without an object filter keeps this working regardless of which
        // NSColorPanel instance SwiftUI happens to present.
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSWindowDidBecomeVisible"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.positionColorPanel(notification: notification)
        }

        // Fallback: poll the shared color panel visibility transitions.
        colorPanelTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkColorPanelVisibility()
        }
    }

    private func checkColorPanelVisibility() {
        let visible = NSColorPanel.shared.isVisible
        if visible && !lastColorPanelVisible {
            positionColorPanel()
        }
        lastColorPanelVisible = visible
    }

    /// Positions the color panel so its left edge is flush with the right
    /// edge of the settings window and its top aligns with the top of the
    /// settings window. Called whenever the panel becomes visible so the
    /// panel always opens at the desired spot instead of keeping whatever
    /// frame it had from a previous (possibly manual) position.
    private func positionColorPanel(notification: Notification? = nil) {
        let panel = notification?.object as? NSColorPanel ?? NSColorPanel.shared
        guard let settingsWindow = settingsWindow, settingsWindow.isVisible else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: settingsWindow.frame.maxX, y: settingsWindow.frame.maxY - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(settingsWindow.frame) }) {
            let maxX = screen.frame.maxX - size.width
            if origin.x > maxX { origin.x = max(0, maxX) }
            if origin.y < screen.frame.minY { origin.y = screen.frame.minY }
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
    }

    deinit {
        if let observer = phaseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = colorPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        colorPanelTimer?.invalidate()
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func showSettings(engine: PomodoroEngine, store: PomodoroStore) {
        // Activate the app to steal focus from terminal, then make the window
        // key on the next main run loop iteration so activation has a chance
        // to complete first. Doing it synchronously left the window without
        // key status, which kept keyboard focus off the text fields.
        let app = NSRunningApplication.current
        app.activate(options: [.activateAllWindows])

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.isReleasedWhenClosed = false
            window.level = .normal
            self.settingsWindow = window
        }

        guard let window = settingsWindow else { return }

        DispatchQueue.main.async {
            window.contentViewController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(engine)
                    .environmentObject(store)
                    .environmentObject(self)
            )
            window.makeKeyAndOrderFront(nil)
            // Re-apply the centered frame after ordering front so the final
            // frame is the centered one.
            window.setFrameOrigin(NSPoint(
                x: (NSScreen.main?.frame.midX ?? 0) - 250,
                y: (NSScreen.main?.frame.midY ?? 0) - 300
            ))
        }
    }

    func showOverlay(engine: PomodoroEngine, store: PomodoroStore) {
        let screens = NSScreen.screens
        let visibleDisplayIDs = Set(screens.map { displayID(for: $0) })

        // Drop windows whose display is gone (for example an unplugged monitor)
        // so no stale overlay is kept around.
        let removedDisplayIDs = overlayWindows.keys.filter { !visibleDisplayIDs.contains($0) }
        for id in removedDisplayIDs {
            overlayWindows[id]?.close()
            overlayWindows[id] = nil
        }

        for screen in screens {
            let id = displayID(for: screen)
            let window = overlayWindows[id] ?? makeOverlayWindow(for: screen)
            overlayWindows[id] = window

            // Assigning a content view controller resizes the window to the
            // controller's preferred size, so the frame has to be applied
            // afterwards or the overlay collapses to a zero-sized window.
            window.contentViewController = NSHostingController(
                rootView: OverlayView(engine: engine).environmentObject(store)
            )
            window.setFrame(screen.frame, display: true)
            window.level = overlayWindowLevel(for: screen)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func hideOverlay() {
        for window in overlayWindows.values {
            window.close()
        }
        overlayWindows.removeAll()
    }

    /// Builds a borderless, opaque window that covers one screen.
    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Resting"
        // NSWindow releases itself when closed by default (isReleasedWhenClosed
        // defaults to YES), which would free the window while we still hold the
        // reference; the subsequent release would then operate on freed memory.
        // Own the release lifecycle ourselves.
        window.isReleasedWhenClosed = false
        // Stay on every Space and above other apps' full-screen Spaces, so
        // switching desktops or entering full screen cannot dismiss the overlay.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.level = overlayWindowLevel(for: screen)
        return window
    }

    /// A window level above the menu bar, the Dock and the screen saver so the
    /// overlay covers all of them.
    private func overlayWindowLevel(for screen: NSScreen) -> NSWindow.Level {
        NSWindow.Level(rawValue: Int(screen.frame.size.height) + 2000)
    }

    /// Stable identity for a display, used to reuse one overlay per screen.
    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    func closeSettings() {
        // SwiftUI's ColorPicker presents via NSColorPanel, which lives outside
        // the SwiftUI view hierarchy. Close it explicitly so an open picker
        // does not linger next to a settings window that is already closing.
        NSColorPanel.shared.close()
        settingsWindow?.close()
        settingsWindow = nil
    }

    /// Registers / unregisters the app as a login item so macOS launches it
    /// automatically at computer boot. Called from the settings "auto launch"
    /// toggle; the actual launch at login is then handled by launchd.
    func setAutoLaunchEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        if enabled {
            _ = try? service.register()
        } else {
            _ = try? service.unregister()
        }
    }
}
