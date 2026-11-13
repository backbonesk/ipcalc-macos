import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private lazy var window: NSWindow = {
        // A fixed size: letting the window follow the grouped Form's preferred size makes AppKit
        // loop on constraint updates (each resize changes the safe area, which changes the size).
        let controller = NSHostingController(rootView: SettingsView())
        controller.sizingOptions = []
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(SettingsView.size)
        window.title = "IP Calc Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { PanelController.shared.refocus() }
        }
        return window
    }()

    var isVisible: Bool { window.isVisible }

    /// Opens Settings next to the panel (which stays visible), so changes can be seen live.
    func show() {
        position()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func position() {
        guard let panel = PanelController.shared.visibleFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel) })?.visibleFrame
        else {
            window.center()
            return
        }
        let size = window.frame.size
        let gap: CGFloat = 16
        let top = min(panel.maxY, screen.maxY)
        if panel.maxX + gap + size.width <= screen.maxX {
            window.setFrameTopLeftPoint(NSPoint(x: panel.maxX + gap, y: top))
        } else if panel.minX - gap - size.width >= screen.minX {
            window.setFrameTopLeftPoint(NSPoint(x: panel.minX - gap - size.width, y: top))
        } else {
            window.setFrameTopLeftPoint(NSPoint(x: panel.midX - size.width / 2, y: panel.minY - gap))
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(SettingsKey.closeAfterCopy) private var closeAfterCopy = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = Appearance.defaultFontSize
    @AppStorage(SettingsKey.showBinary) private var showBinary = true
    @AppStorage(SettingsKey.showNotes) private var showNotes = true
    @AppStorage(SettingsKey.labelOpacity) private var labelOpacity = 1.0
    @AppStorage(SettingsKey.valueColor) private var valueColor = ""
    @AppStorage(SettingsKey.netmaskColor) private var netmaskColor = ""
    @AppStorage(SettingsKey.accentColor) private var accentColor = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    private let hotKeys = HotKeyCenter.shared

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Shortcut") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder()
                        if !hotKeys.isRegistered {
                            Text("Already used by another app. Pick a different shortcut.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                Picker("After copying", selection: $closeAfterCopy) {
                    Text("Close panel").tag(true)
                    Text("Keep panel open").tag(false)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("To get back here, open IP Calc from Finder or press ⌘, in the panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $fontSize, in: Appearance.fontSizes, step: 1)
                            .frame(width: 160)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Label brightness") {
                    HStack {
                        Slider(value: $labelOpacity, in: Appearance.labelOpacities, step: 0.05)
                            .frame(width: 160)
                        Text("\(Int((labelOpacity * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Show binary column", isOn: $showBinary)
                Toggle("Show notes (address class, 2^n)", isOn: $showNotes)
                ColorSetting(title: "Values", stored: $valueColor, defaultColor: Appearance.defaultValue)
                ColorSetting(title: "Netmask bits", stored: $netmaskColor, defaultColor: Appearance.defaultNetmask)
                ColorSetting(title: "Class bits and notes", stored: $accentColor, defaultColor: Appearance.defaultAccent)
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        fontSize = Appearance.defaultFontSize
                        showBinary = true
                        showNotes = true
                        labelOpacity = 1
                        valueColor = ""
                        netmaskColor = ""
                        accentColor = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    static let size = CGSize(width: 460, height: 680)

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}

/// A color well bound to a `#RRGGBB` string; empty means the adaptive system default.
private struct ColorSetting: View {
    let title: String
    @Binding var stored: String
    let defaultColor: Color

    var body: some View {
        LabeledContent(title) {
            HStack {
                if !stored.isEmpty {
                    Button("Default") { stored = "" }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                ColorPicker(title, selection: Binding(
                    get: { Color(hex: stored) ?? defaultColor },
                    set: { stored = $0.hex }
                ), supportsOpacity: false)
                .labelsHidden()
            }
        }
    }
}

/// Click, then press the new shortcut. ⎋ cancels.
private struct ShortcutRecorder: View {
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? "Press shortcut…" : HotKeyCenter.shared.shortcut.display)
                .frame(minWidth: 110)
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func start() {
        // Unregister so pressing the current shortcut reaches the recorder instead of toggling the panel.
        HotKeyCenter.shared.unregister()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
            } else if let shortcut = Shortcut(event: event) {
                HotKeyCenter.shared.set(shortcut)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotKeyCenter.shared.register()
    }
}
