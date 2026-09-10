import SwiftUI
import AppKit

/// An `NSTextView`-backed SQL editor with lightweight syntax highlighting (keywords,
/// strings, comments, numbers) in JetBrains Mono. Replaces SwiftUI's plain `TextEditor`.
struct SQLEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = Highlighter.font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = text
        Highlighter.apply(to: textView.textStorage)
        scroll.drawsBackground = false
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        Highlighter.apply(to: textView.textStorage)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            let selected = textView.selectedRanges
            Highlighter.apply(to: textView.textStorage)
            textView.selectedRanges = selected
        }
    }
}

/// Regex-based SQL highlighter, applied to the text storage on each edit (main-thread only).
@MainActor
private enum Highlighter {
    static let font = NSFont(name: "JetBrains Mono", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)

    private static let text = stratum(0x223038, 0xE3E5EA)
    private static let keyword = stratum(0x1E7A72, 0x3FA091)
    private static let number = stratum(0xA97B36, 0xD6A55D)
    private static let string = stratum(0x3E7C4F, 0x86C58E)
    private static let comment = stratum(0x8B8B84, 0x6E807C)

    private static let keywords = [
        "select", "from", "where", "group", "by", "order", "having", "limit", "offset",
        "join", "left", "right", "inner", "outer", "full", "cross", "on", "using", "as",
        "and", "or", "not", "null", "is", "in", "like", "ilike", "between", "exists",
        "case", "when", "then", "else", "end", "with", "recursive", "union", "except",
        "intersect", "all", "distinct", "cast", "try_cast", "at", "version", "timestamp",
        "asc", "desc", "nulls", "first", "last", "over", "partition", "qualify", "sample",
        "pivot", "unpivot", "exclude", "replace", "values", "attach", "use", "summarize",
        "true", "false", "interval", "date", "coalesce", "filter", "window",
    ]

    private static let patterns: [(NSRegularExpression, NSColor)] = {
        let kw = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"
        func re(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
            try! NSRegularExpression(pattern: p, options: opts)
        }
        return [
            (re(kw, [.caseInsensitive]), keyword),
            (re("\\b\\d+(?:\\.\\d+)?\\b"), number),
            (re("'(?:[^'\\\\]|\\\\.)*'"), string),   // strings (win over keywords/numbers)
            (re("--[^\\n]*"), comment),               // line comments (win over all)
        ]
    }()

    static func apply(to storage: NSTextStorage?) {
        guard let storage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: text], range: full)
        for (regex, color) in patterns {
            regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
                if let range = match?.range {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        storage.endEditing()
    }

    private static func stratum(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}
