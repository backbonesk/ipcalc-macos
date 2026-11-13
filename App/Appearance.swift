import AppKit
import SwiftUI

enum SettingsKey {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let closeAfterCopy = "closeAfterCopy"
    static let fontSize = "fontSize"
    static let showBinary = "showBinary"
    static let showNotes = "showNotes"
    static let labelOpacity = "labelOpacity"
    static let valueColor = "valueColor"
    static let netmaskColor = "netmaskColor"
    static let accentColor = "accentColor"
}

/// Visual settings read by the panel. Colors are stored as `#RRGGBB`; an empty string means the
/// system color, which adapts to light and dark mode.
struct Appearance {
    static let defaultFontSize = 13.0
    static let fontSizes = 10.0...20.0
    static let labelOpacities = 0.3...1.0

    var fontSize: Double
    var showBinary: Bool
    var showNotes: Bool
    /// Opacity of row labels and section titles.
    var labelOpacity: Double
    var value: Color
    var netmask: Color
    /// Class bits and notes.
    var accent: Color

    var font: NSFont { .monospacedSystemFont(ofSize: fontSize, weight: .regular) }
    var charWidth: CGFloat { ("0" as NSString).size(withAttributes: [.font: font]).width }
    /// The input scales with the results, but stays large like Spotlight's.
    var inputFontSize: CGFloat { max(20, fontSize * 1.8) }

    static let defaultValue = Color.blue
    static let defaultNetmask = Color.red
    static let defaultAccent = Color.green
}

extension Color {
    init?(hex: String) {
        guard hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double(rgb >> 16 & 0xFF) / 255,
                  green: Double(rgb >> 8 & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }

    var hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }
}
