import SwiftUI
import AppKit
import ServiceManagement
import MustRest

class WindowManager: ObservableObject {
    /// Weak reference used by the app delegate to refuse quitting while the
    /// blocking overlay is on screen.
    private(set) static weak var active: WindowManager?

    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    /// One overlay window per display, keyed by display ID, so every screen is
    /// covered instead of only the main one.
    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]
    /// True while the blocking overlay is displayed. While set, quitting the
    /// app is refused and the system is put in kiosk presentation mode.
    private(set) var isBlockingOverlay = false
    private weak var engine: PomodoroEngine?
    private var phaseObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var colorPanelObserver: NSObjectProtocol?
    private var colorPanelTimer: Timer?
    private var lastColorPanelVisible = false
    private var keyMonitor: Any?
    /// Remaining seconds of the Escape long press while it is being held, or
    /// nil when Escape is not pressed. Drives the overlay countdown text.
    @Published private(set) var escapeHoldRemainingSeconds: Int?
    /// Timer backing the long-press Escape escape hatch.
    private var escapeHoldTimer: Timer?
    /// Throttles re-activation attempts triggered by losing focus.
    private var lastKioskReassert = Date.distantPast

    init() {
        // A menu bar only app must run with an accessory activation policy,
        // otherwise it shows up in the Dock and the Command + Tab switcher.
        NSApp.setActivationPolicy(.accessory)
        WindowManager.active = self
        setupPhaseObserver()
        setupResignActiveObserver()
        setupBecomeActiveObserver()
        setupColorPanelObserver()
        setupKeyMonitor()
    }

    /// While the blocking overlay is visible, losing focus would silently drop
    /// the kiosk presentation options, so take the focus back. Throttled so a
    /// system UI that keeps stealing activation cannot cause a tight loop.
    private func setupResignActiveObserver() {
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isBlockingOverlay else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastKioskReassert) >= 0.5 else { return }
            self.lastKioskReassert = now
            self.activateOverlayApp()
            self.enterKioskMode()
        }
    }

    /// Re-keys the overlay whenever the app becomes active again, so the Escape
    /// long press keeps working after the system stole focus.
    private func setupBecomeActiveObserver() {
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.makeOverlayKey()
        }
    }

    private func setupKeyMonitor() {
        // Escape closes the settings window. While an overlay is visible and
        // manual exit is allowed, holding Escape for a few seconds ends the
        // break. The blocking overlay swallows Escape instead, because it must
        // not offer any way out.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }
            guard event.keyCode == 53 else { return event }
            if !self.overlayWindows.isEmpty {
                guard !self.isBlockingOverlay else { return nil }
                if event.type == .keyDown {
                    if !event.isARepeat {
                        self.beginEscapeHold()
                    }
                } else {
                    self.cancelEscapeHold()
                }
                return nil
            }
            if event.type == .keyDown {
                if self.aboutWindow?.isKeyWindow == true {
                    self.aboutWindow?.close()
                } else {
                    self.closeSettings()
                }
            }
            return nil
        }
    }

    /// Seconds Escape has to be held before the overlay can be dismissed.
    private static let escapeHoldDuration: TimeInterval = 3

    private func beginEscapeHold() {
        // A break that ends within the hold duration cannot be skipped anyway,
        // and starting the 3-2-1 countdown would clash with the overlay's own
        // final seconds, so ignore the hold in that case.
        if let engine = engine, engine.remainingSeconds <= Self.escapeHoldDuration {
            return
        }
        cancelEscapeHold()
        let total = Int(Self.escapeHoldDuration)
        escapeHoldRemainingSeconds = total
        var remaining = total
        // Tick once per second so the overlay counts down 3, 2, 1 while the
        // key is held. Releasing the key cancels the timer.
        escapeHoldTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            remaining -= 1
            if remaining > 0 {
                self.escapeHoldRemainingSeconds = remaining
            } else {
                timer.invalidate()
                self.escapeHoldTimer = nil
                self.escapeHoldRemainingSeconds = nil
                self.endOverlayByEscape()
            }
        }
    }

    private func cancelEscapeHold() {
        escapeHoldTimer?.invalidate()
        escapeHoldTimer = nil
        escapeHoldRemainingSeconds = nil
    }

    private func endOverlayByEscape() {
        escapeHoldTimer?.invalidate()
        escapeHoldTimer = nil
        escapeHoldRemainingSeconds = nil
        engine?.skipCurrentBreak()
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
        if let observer = resignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = becomeActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = colorPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        colorPanelTimer?.invalidate()
        escapeHoldTimer?.invalidate()
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
                rootView: OverlayView(engine: engine)
                    .environmentObject(store)
                    .environmentObject(self)
            )
            window.setFrame(screen.frame, display: true)
            window.level = overlayWindowLevel
            window.makeKeyAndOrderFront(nil)
        }

        self.engine = engine
        activateOverlayApp()
        if store.settings.isOverlayBlocking {
            if !isBlockingOverlay {
                isBlockingOverlay = true
                enterKioskMode()
            }
        } else {
            leaveKioskMode()
        }
    }

    func hideOverlay() {
        for window in overlayWindows.values {
            window.close()
        }
        overlayWindows.removeAll()
        leaveKioskMode()
    }

    /// Brings the app to the front and gives an overlay window keyboard focus.
    /// A local key monitor only receives key events while the app is active and
    /// one of its windows is key, which the Escape long press depends on.
    ///
    /// On macOS 14+ activation is cooperative: `NSApp.activate()` and
    /// `NSRunningApplication.activate` are refused for an app that was
    /// triggered from the background, while the older
    /// `activate(ignoringOtherApps:)` still forces it through.
    private func activateOverlayApp() {
        NSApp.activate()
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Activation is asynchronous, so key the window once it takes effect.
        DispatchQueue.main.async { [weak self] in
            self?.makeOverlayKey()
        }
    }

    /// Makes one visible overlay window the key window. Multiple displays only
    /// need a single key window because the local monitor is app-wide.
    private func makeOverlayKey() {
        guard let window = overlayWindows.values.first(where: { $0.isVisible }) else { return }
        if NSApp.keyWindow !== window {
            window.makeKey()
        }
    }

    /// Blocks Command + Tab, Force Quit, log out / shut down and the Dock while
    /// the blocking overlay is visible, so the user cannot walk away from the
    /// break with system shortcuts.
    private func enterKioskMode() {
        // Presentation options only take effect while this app is active, so
        // the overlay is activated right before this is called.
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableAppleMenu,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
        ]
    }

    private func leaveKioskMode() {
        cancelEscapeHold()
        isBlockingOverlay = false
        NSApp.presentationOptions = []
    }

    /// Builds a borderless, opaque window that covers one screen.
    private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = OverlayWindow(
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
        window.level = overlayWindowLevel
        return window
    }

    /// Just above the screen saver level: high enough to cover the menu bar,
    /// the Dock, notification banners and other screen-saver-level overlays,
    /// while staying below the lock screen and accessibility UI.
    private var overlayWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
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

    /// Shows the About window with the author's WeChat QR code. Reuses the
    /// same window so reopening it does not stack duplicates.
    func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "关于 MustRest"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: AboutView())
            // Assigning a content view controller resizes the window, so the
            // final size has to be applied afterwards.
            window.setContentSize(NSSize(width: 420, height: 620))
            window.center()
            aboutWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
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

/// Borderless overlay window that is allowed to become key, so it receives the
/// keyboard events used for the long-press Escape escape hatch.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
