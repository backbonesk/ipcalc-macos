import AppKit
import IPCalcKit
import SwiftUI

/// Column layout of a report in points. All text is monospaced, so widths follow from character
/// counts and the panel can be sized exactly to its content.
struct ReportMetrics {
    static let labelChars = 11
    static let outerPadding: CGFloat = 10
    static let rowPadding: CGFloat = 10
    static let minSpacer: CGFloat = 12

    let appearance: Appearance
    let charWidth: CGFloat
    /// Characters of the value column, so binary and notes line up; 0 when nothing follows values.
    let valueChars: Int
    /// Width the report needs without shrinking anything.
    let naturalWidth: CGFloat

    var copyButtonWidth: CGFloat { (appearance.fontSize * 1.4).rounded() }
    /// Everything in a row except label, value and trailing columns.
    var chrome: CGFloat { 2 * Self.outerPadding + 2 * Self.rowPadding + Self.minSpacer + copyButtonWidth }

    init(report: IPCalcReport, appearance: Appearance) {
        self.appearance = appearance
        charWidth = appearance.charWidth
        let fields = report.fields
        let valueChars = fields
            .filter { !$0.label.isEmpty && Self.trailingChars($0, appearance) > 0 }
            .map { $0.value.count + 2 }
            .max() ?? 0
        self.valueChars = valueChars

        var widest = fields.map { field in
            guard !field.label.isEmpty else { return field.value.count }
            let trailing = Self.trailingChars(field, appearance)
            return Self.labelChars + (trailing > 0 ? valueChars + trailing : field.value.count)
        }.max() ?? 0
        for section in report.sections {
            widest = max(widest, section.title?.count ?? 0)
            for case .text(let text) in section.lines {
                widest = max(widest, text.count)
            }
        }
        naturalWidth = CGFloat(widest) * charWidth + 2 * Self.outerPadding + 2 * Self.rowPadding
            + Self.minSpacer + (appearance.fontSize * 1.4).rounded() + 1
    }

    static func trailingChars(_ field: IPCalcReport.Field, _ appearance: Appearance) -> Int {
        let binary = appearance.showBinary ? field.binary?.text.count ?? 0 : 0
        let note = appearance.showNotes ? field.note.map { $0.text.count + 2 } ?? 0 : 0
        return binary + note + (binary > 0 && note > 0 ? 1 : 0)
    }
}

/// Renders an `IPCalcReport` as Spotlight-style rows in the ipcalc column layout.
/// Each field row is selectable, has a copy button and a context menu. When `width` is smaller
/// than the natural width, only values that no longer fit are drawn smaller.
struct ReportView: View {
    let report: IPCalcReport
    let metrics: ReportMetrics
    let width: CGFloat
    var selection: Int?
    var onSelect: (Int) -> Void
    var onCopy: (String) -> Void

    private var appearance: Appearance { metrics.appearance }
    private var charWidth: CGFloat { metrics.charWidth }
    private var rowPadding: CGFloat { (appearance.fontSize * 0.25).rounded() }
    private var shrink: CGFloat { max(0, metrics.naturalWidth - width) }

    var body: some View {
        VStack(alignment: .leading, spacing: appearance.fontSize) {
            ForEach(Array(report.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 0) {
                    if let title = section.title {
                        Text(title).bold()
                            .opacity(appearance.labelOpacity)
                            .lineLimit(1)
                            .padding(.horizontal, ReportMetrics.rowPadding)
                            .padding(.bottom, 2)
                    }
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
            }
        }
        .font(Font(appearance.font))
        .padding(ReportMetrics.outerPadding)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ line: IPCalcReport.Line) -> some View {
        switch line {
        case .arrow:
            Text(" ").padding(.horizontal, ReportMetrics.rowPadding).padding(.vertical, rowPadding)
        case .text(let text):
            Text(text).foregroundStyle(.secondary).lineLimit(1)
                .padding(.horizontal, ReportMetrics.rowPadding).padding(.vertical, rowPadding)
        case .field(let field):
            fieldRow(field)
        }
    }

    /// Value cell width: the shared column when something follows, otherwise the value itself,
    /// reduced by however much the panel is narrower than the content.
    private func valueWidth(_ field: IPCalcReport.Field, hasTrailing: Bool) -> CGFloat {
        let natural = CGFloat(hasTrailing ? metrics.valueChars : field.value.count) * charWidth
        let available = width - metrics.chrome - (field.label.isEmpty ? 0 : CGFloat(ReportMetrics.labelChars) * charWidth)
        let target = hasTrailing ? natural - shrink : min(natural, available)
        return max(target, 6 * charWidth) + 1
    }

    private func fieldRow(_ field: IPCalcReport.Field) -> some View {
        let showsBinary = appearance.showBinary && field.binary != nil
        let showsNote = appearance.showNotes && field.note != nil
        return HStack(spacing: 0) {
            if !field.label.isEmpty {
                Text(field.label)
                    .opacity(appearance.labelOpacity)
                    .frame(width: CGFloat(ReportMetrics.labelChars) * charWidth, alignment: .leading)
            }
            Text(field.value)
                .foregroundStyle(appearance.value)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: valueWidth(field, hasTrailing: showsBinary || showsNote), alignment: .leading)
            HStack(spacing: charWidth) {
                if showsBinary, let binary = field.binary {
                    BinaryText(binary: binary, appearance: appearance)
                }
                if showsNote, let note = field.note {
                    Text("(\(note.text))").foregroundStyle(appearance.accent)
                }
            }
            .fixedSize()
            Spacer(minLength: ReportMetrics.minSpacer)
            Button {
                onCopy(field.copyValue)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .frame(width: metrics.copyButtonWidth)
            .help("Copy \(field.copyValue)")
        }
        .padding(.horizontal, ReportMetrics.rowPadding)
        .padding(.vertical, rowPadding)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(selection == field.index ? Color.accentColor.opacity(0.3) : .clear)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(field.index) }
        .contextMenu {
            Button("Copy Value") { onCopy(field.copyValue) }
            Button("Copy Row") { onCopy(field.plainLine) }
            if let binary = field.binary {
                Button("Copy Binary") { onCopy(binary.text) }
            }
        }
        .id(field.index)
    }
}

private struct BinaryText: View {
    let binary: IPCalcReport.Binary
    let appearance: Appearance

    var body: some View {
        let head = String(binary.text.prefix(binary.classBits))
        let tail = String(binary.text.dropFirst(binary.classBits))
        let tailColor = binary.style == .netmask ? appearance.netmask : Color.secondary
        Text("\(Text(head).foregroundStyle(appearance.accent))\(Text(tail).foregroundStyle(tailColor))")
    }
}
