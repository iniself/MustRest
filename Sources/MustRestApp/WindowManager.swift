import SwiftUI
import AppKit
import MustRest

class WindowManager: ObservableObject {
    private var settingsWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var phaseObserver: NSObjectProtocol?

    init() {
        // A menu bar only app must run with a regular activation policy,
        // otherwise NSApplication never enters the active state and windows
        // can never become key windows.
        NSApp.setActivationPolicy(.regular)
        setupPhaseObserver()
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

    deinit {
        if let observer = phaseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showSettings(engine: PomodoroEngine, store: PomodoroStore) {
        NSLog("[WindowManager] showSettings called")
        NSLog("[WindowManager] Current app: \(NSRunningApplication.current.localizedName ?? "Unknown")")

        // Activate the app to steal focus from terminal, then make the window
        // key on the next main run loop iteration so activation has a chance
        // to complete first. Doing it synchronously left the window without
        // key status, which kept keyboard focus off the text fields.
        let app = NSRunningApplication.current
        let didActivate = app.activate(options: [.activateAllWindows])
        NSLog("[WindowManager] activate returned \(didActivate), NSApp.isActive: \(NSApp.isActive), policy: \(NSApp.activationPolicy)")

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "设置"
            window.center()
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
            NSLog("[WindowManager] Settings window isKeyWindow: \(window.isKeyWindow), visible: \(window.isVisible), NSApp.keyWindow: \(NSApp.keyWindow)")
        }
    }

    func showOverlay(engine: PomodoroEngine, store: PomodoroStore) {
        print("[WindowManager] Show Overlay requested")
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Resting"
            window.level = NSWindow.Level(rawValue: Int(NSScreen.main?.frame.size.height ?? 1080) + 2000)
            self.overlayWindow = window
        }

        if let window = overlayWindow {
            let contentView = OverlayView(engine: engine)
                .environmentObject(store)
            window.contentViewController = NSHostingController(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            print("[WindowManager] Overlay displayed")
        }
    }

    func hideOverlay() {
        print("[WindowManager] Hiding overlay...")
        overlayWindow?.close()
        overlayWindow = nil
    }

    func closeSettings() {
        settingsWindow?.close()
        settingsWindow = nil
    }
}
