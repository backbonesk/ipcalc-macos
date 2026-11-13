import IPCalcKit
import SwiftUI

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var input = UserDefaults.standard.string(forKey: "lastInput") ?? "" {
        didSet { UserDefaults.standard.set(input, forKey: "lastInput") }
    }

    /// Bumped every time the panel is shown, so the input gets focused with its text selected.
    var presentations = 0
    /// Limits from the screen the panel is shown on.
    var maxPanelWidth: CGFloat = 1200
    var maxReportHeight: CGFloat = 520
}

/// The panel content: a Spotlight-style input with the live report below it.
struct ContentView: View {
    @Bindable private var model = AppModel.shared
    @State private var selection: Int?
    @State private var copiedMessage: String?
    @State private var reportHeight: CGFloat = 0
    @AppStorage(SettingsKey.closeAfterCopy) private var closeAfterCopy = true
    @AppStorage(SettingsKey.fontSize) private var fontSize = Appearance.defaultFontSize
    @AppStorage(SettingsKey.showBinary) private var showBinary = true
    @AppStorage(SettingsKey.showNotes) private var showNotes = true
    @AppStorage(SettingsKey.labelOpacity) private var labelOpacity = 1.0
    @AppStorage(SettingsKey.valueColor) private var valueColor = ""
    @AppStorage(SettingsKey.netmaskColor) private var netmaskColor = ""
    @AppStorage(SettingsKey.accentColor) private var accentColor = ""
    private let onClose: () -> Void
    private let onSizeChange: (CGSize) -> Void

    private static let minWidth: CGFloat = 600

    init(onClose: @escaping () -> Void, onSizeChange: @escaping (CGSize) -> Void) {
        self.onClose = onClose
        self.onSizeChange = onSizeChange
    }

    private var appearance: Appearance {
        Appearance(fontSize: fontSize,
                   showBinary: showBinary,
                   showNotes: showNotes,
                   labelOpacity: labelOpacity,
                   value: Color(hex: valueColor) ?? Appearance.defaultValue,
                   netmask: Color(hex: netmaskColor) ?? Appearance.defaultNetmask,
                   accent: Color(hex: accentColor) ?? Appearance.defaultAccent)
    }

    private var result: Result<IPCalcReport, IPCalcError> {
        Result { () throws(IPCalcError) in try IPCalc.report(for: model.input) }
    }

    /// Fits the result, but never narrower than a comfortable input or wider than the screen.
    private var panelWidth: CGFloat {
        guard case .success(let report) = result, hasInput else { return Self.minWidth }
        let natural = ReportMetrics(report: report, appearance: appearance).naturalWidth
        return min(max(natural, Self.minWidth), model.maxPanelWidth).rounded(.up)
    }

    private var hasInput: Bool {
        !model.input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: appearance.inputFontSize * 0.9))
                    .foregroundStyle(.secondary)
                SearchField(text: $model.input,
                            placeholder: "IP address, network or range",
                            fontSize: appearance.inputFontSize,
                            focusRequest: model.presentations,
                            onCommand: handle)
                // The field only takes the width of its text; the rest of the row drags the panel.
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(height: (appearance.inputFontSize * 2.5).rounded())

            if hasInput {
                Divider()
                results
                Divider()
                footer
            }
        }
        .frame(width: panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSizeChange($0) }
        .onChange(of: model.input) { selection = nil }
    }

    @ViewBuilder
    private var results: some View {
        switch result {
        case .success(let report):
            ScrollViewReader { proxy in
                ScrollView {
                    ReportView(report: report,
                               metrics: ReportMetrics(report: report, appearance: appearance),
                               width: panelWidth,
                               selection: selection,
                               onSelect: { selection = $0 },
                               onCopy: { copy($0) })
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { reportHeight = $0 }
                }
                .frame(height: min(reportHeight, model.maxReportHeight))
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selection) { _, index in
                    if let index { proxy.scrollTo(index) }
                }
            }
        case .failure(let error):
            Text(error.localizedDescription)
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(copiedMessage ?? "↑↓ select · ↩ copy value · ⇧↩ copy row · esc close")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if case .success(let report) = result {
                Button {
                    copy(report.plainText, message: "Copied all")
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy all (⇧⌘C)")
            }
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit IP Calc (⌘Q)")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func handle(_ command: SearchField.Command) -> Bool {
        if case .escape = command {
            onClose()
            return true
        }
        guard case .success(let report) = result, !report.fields.isEmpty else { return false }
        let fields = report.fields
        switch command {
        case .down:
            selection = min((selection ?? -1) + 1, fields.count - 1)
        case .up:
            selection = max((selection ?? fields.count) - 1, 0)
        case .enter(let shift):
            guard let selection, fields.indices.contains(selection) else { return false }
            copy(shift ? fields[selection].plainLine : fields[selection].copyValue)
        case .escape:
            break
        }
        return true
    }

    /// Copies and, by default, hides the panel so focus returns to the previous app, ready for ⌘V.
    private func copy(_ value: String, message: String? = nil) {
        Pasteboard.copy(value)
        if closeAfterCopy {
            onClose()
            return
        }
        let text = message ?? "Copied \(value)"
        copiedMessage = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedMessage == text { copiedMessage = nil }
        }
    }
}

enum Pasteboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
