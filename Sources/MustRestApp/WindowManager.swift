import SwiftUI
import AppKit
import MustRest

class WindowManager: ObservableObject {
    private var settingsWindow: NSWindow?
    private var overlayWindow: NSWindow?
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
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Resting"
            // NSWindow releases itself when closed by default (isReleasedWhenClosed
            // defaults to YES), which would free the window while we still hold the
            // reference; the subsequent `overlayWindow = nil` would then release the
            // already-freed window and crash. Own the release lifecycle ourselves.
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(NSScreen.main?.frame.size.height ?? 1080) + 2000)
            self.overlayWindow = window
        }

        if let window = overlayWindow {
            let contentView = OverlayView(engine: engine)
                .environmentObject(store)
            window.contentViewController = NSHostingController(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            // The overlay must cover the whole screen; make sure the window has
            // a concrete frame before making it visible, otherwise it renders as
            // a zero-sized (invisible) window.
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
            if window.frame.size.width <= 0 || window.frame.size.height <= 0 {
                window.setFrame(screenFrame, display: true)
            }
        }
    }

    func hideOverlay() {
        overlayWindow?.close()
        overlayWindow = nil
    }

    func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
    }
}
