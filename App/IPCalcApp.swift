import SwiftUI

/// IP Calc is an agent app (no Dock icon). Its UI is a Spotlight-like panel toggled by a global
/// shortcut, plus an optional menu bar icon and a Settings window.
@main
struct IPCalcApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("IP Calc", systemImage: "network", isInserted: $showMenuBarIcon) {
            Button("Show IP Calc (\(HotKeyCenter.shared.shortcut.display))") {
                PanelController.shared.show()
            }
            Button("Settings…") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",")
            Divider()
            Button("Quit IP Calc") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyCenter.shared.onPress = { PanelController.shared.toggle() }
        HotKeyCenter.shared.register()
        if !launchedAsLoginItem {
            PanelController.shared.show()
        }
    }

    /// Opening the app again (Finder, Launchpad) shows the panel; this is also the way back to
    /// Settings when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

@MainActor
final class PanelController {
    static let shared = PanelController()
    static let cornerRadius: CGFloat = 26

    /// Top-center of the panel when it was last hidden, so it reopens where the user left it.
    /// Kept in memory only: a fresh start opens centered again.
    private var anchor: NSPoint?

    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 60),
            // Non-activating like Spotlight: it takes keyboard input without activating the app,
            // so focus returns to the previous app when it hides.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: ContentView(
            onClose: { [weak self] in self?.hide() },
            onSizeChange: { [weak self] in self?.setSize($0) }
        ))
        // Clip to the glass shape so the window shadow follows the rounded corners instead of
        // outlining the rectangular window (visible as a hairline frame on light backgrounds).
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = Self.cornerRadius
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        // When Settings had made the app active, leaving the app hides the panel as well.
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PanelController.shared.hide() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                               object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { PanelController.shared.updateLimits() }
        }
        return panel
    }()

    /// The panel's frame while it is on screen.
    var visibleFrame: NSRect? {
        panel.isVisible ? panel.frame : nil
    }

    func toggle() {
        panel.isKeyWindow ? hide() : show()
    }

    func show() {
        if !panel.isVisible {
            let top = anchor.flatMap { anchor in
                NSScreen.screens.contains { NSPointInRect(anchor, $0.frame) } ? anchor : nil
            } ?? defaultAnchor()
            panel.setFrameTopLeftPoint(NSPoint(x: top.x - panel.frame.width / 2, y: top.y))
            updateLimits()
        }
        AppModel.shared.presentations += 1
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        if panel.isVisible {
            anchor = NSPoint(x: panel.frame.midX, y: panel.frame.maxY)
        }
        panel.orderOut(nil)
    }

    /// Centered on the screen with the mouse, with the input where Spotlight's is.
    private func defaultAnchor() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(x: frame.midX, y: frame.maxY - frame.height * 0.2)
    }

    /// Size limits from the screen the panel is on and how far down it sits.
    func updateLimits() {
        let frame = panel.frame
        guard let screen = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        AppModel.shared.maxPanelWidth = screen.width - 80
        // Leave room for the input and footer above and the screen edge below.
        AppModel.shared.maxReportHeight = max(200, frame.maxY - screen.minY - 180)
    }

    /// Gives the panel keyboard focus again, e.g. after the Settings window closes.
    func refocus() {
        if panel.isVisible { panel.makeKey() }
    }

    /// Grows or shrinks the panel downwards and around its center, keeping the input in place.
    private func setSize(_ size: CGSize) {
        var frame = panel.frame
        let top = frame.maxY
        let center = frame.midX
        frame.size = CGSize(width: ceil(size.width), height: ceil(size.height))
        frame.origin = CGPoint(x: center - frame.width / 2, y: top - frame.height)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Drag the panel from anywhere except the text field, like Spotlight. A mouse-down is held back
    /// until it is clear whether the mouse moves: a drag of more than a few points moves the panel,
    /// anything else is delivered unchanged, so clicks, row selection and buttons keep working.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, !isOverTextField(event) else {
            super.sendEvent(event)
            return
        }
        var held: [NSEvent] = []
        let start = event.locationInWindow
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseDragged,
               hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y) > 3 {
                performDrag(with: event)
                return
            }
            held.append(next)
            if next.type == .leftMouseUp { break }
        }
        super.sendEvent(event)
        held.forEach { super.sendEvent($0) }
    }

    private func isOverTextField(_ event: NSEvent) -> Bool {
        guard let frameView = contentView?.superview,
              let hit = frameView.hitTest(frameView.convert(event.locationInWindow, from: nil))
        else { return false }
        return hit is NSText || hit is NSTextField
    }

    // Hide like Spotlight as soon as the user clicks elsewhere, but stay visible while one of our
    // own windows (Settings) has focus, so changes can be previewed.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, !isKeyWindow, !SettingsWindowController.shared.isVisible else { return }
            PanelController.shared.hide()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.hide()
    }
}
