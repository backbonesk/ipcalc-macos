import AppKit
import SwiftUI

/// The large Spotlight-style input. Wraps NSTextField so we can select all text when the panel
/// reopens and intercept ↑ ↓ ↩ ⎋ before the field editor handles them.
struct SearchField: NSViewRepresentable {
    enum Command {
        case up, down, escape
        case enter(shift: Bool)
    }

    @Binding var text: String
    var placeholder: String
    var fontSize: CGFloat
    /// Changing this value focuses the field and selects its whole text.
    var focusRequest: Int
    /// Returns true when the command was handled.
    var onCommand: (Command) -> Bool

    func makeNSView(context: Context) -> FittingTextField {
        let field = FittingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FittingTextField, context: Context) {
        context.coordinator.parent = self
        if field.font?.pointSize != fontSize {
            field.font = .systemFont(ofSize: fontSize)
        }
        if field.stringValue != text {
            field.stringValue = text
            field.invalidateIntrinsicContentSize()
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    /// As wide as the text (or placeholder), so the space to its right stays free for dragging.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FittingTextField, context: Context) -> CGSize? {
        let fitting = nsView.intrinsicContentSize
        return CGSize(width: min(fitting.width, proposal.width ?? fitting.width), height: fitting.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var focusRequest: Int?

        init(parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.invalidateIntrinsicContentSize()
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)):
                parent.onCommand(.down)
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCommand(.escape)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onCommand(.enter(shift: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
            default:
                false
            }
        }
    }
}

/// A text field whose intrinsic width follows its content, plus room for the caret.
final class FittingTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        let text = stringValue.isEmpty ? placeholderString ?? "" : stringValue
        let width = (text as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 24)]).width
        return NSSize(width: ceil(width) + 12, height: super.intrinsicContentSize.height)
    }
}
