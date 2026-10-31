import AppKit
import DYCore
import DYLenses
import SwiftUI

/// Splits SQL text into coloured pieces. Pure, so it can be tested.
public enum SQLHighlighter {
    /// What a piece of text is.
    public enum Token: Equatable { case keyword, function, string, number, comment }

    /// One coloured piece.
    public struct Span: Equatable {
        public var range: NSRange
        public var token: Token
    }

    static let keywords: Set<String> = [
        "select", "from", "where", "group", "by", "order", "having", "limit", "offset", "join", "left", "right", "inner", "outer", "cross",
        "on", "using", "as", "and", "or", "not", "in", "is", "null", "like", "glob", "between", "case", "when", "then", "else", "end",
        "distinct", "union", "all", "except", "intersect", "with", "recursive", "over", "partition", "asc", "desc", "exists", "cast",
        "true", "false", "rows", "range", "unbounded", "preceding", "following", "current", "row", "filter", "values",
    ]

    private static let pattern = try? NSRegularExpression(
        pattern: #"(--[^\n]*)|('(?:[^']|'')*'?)|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)"#)

    /// The coloured pieces of `text`, in order. Anything not listed stays in the plain colour.
    public static func spans(in text: String) -> [Span] {
        guard let pattern else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        let ns = text as NSString
        return pattern.matches(in: text, range: whole).compactMap { match in
            if match.range(at: 1).location != NSNotFound { return Span(range: match.range(at: 1), token: .comment) }
            if match.range(at: 2).location != NSNotFound { return Span(range: match.range(at: 2), token: .string) }
            if match.range(at: 3).location != NSNotFound { return Span(range: match.range(at: 3), token: .number) }
            let range = match.range(at: 4)
            guard range.location != NSNotFound else { return nil }
            let word = ns.substring(with: range).lowercased()
            if keywords.contains(word) { return Span(range: range, token: .keyword) }
            let after = ns.substring(from: range.location + range.length).drop { $0 == " " }
            return after.first == "(" ? Span(range: range, token: .function) : nil
        }
    }

    /// The colour of a token, from the palette's category hues so gold stays reserved.
    static func color(_ token: Token) -> NSColor {
        switch token {
        case .keyword: NSColor(Theme.kind(.document))
        case .function: NSColor(Theme.kind(.image))
        case .string: NSColor(Theme.kind(.application))
        case .number: NSColor(Theme.kind(.archive))
        case .comment: NSColor(Theme.textMuted)
        }
    }
}

/// The text view behind the SQL editor. A class of its own so key routing can tell it from other text fields.
final class SQLTextView: NSTextView {
    var placeholder = ""

    /// Draws the placeholder while the editor is empty.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                                         .foregroundColor: NSColor(Theme.textMuted)]
        placeholder.draw(at: NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height), withAttributes: attributes)
    }
}

/// A plain monospaced SQL editor with light highlighting. `⌘⏎` is handled by the window's key routing, not here.
struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var placeholder = "SELECT id, name FROM files ORDER BY size DESC LIMIT 100"

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let view = SQLTextView(frame: .zero)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isGrammarCheckingEnabled = false
        view.drawsBackground = false
        view.font = Self.font
        view.textColor = NSColor(Theme.textPrimary)
        view.insertionPointColor = NSColor(Theme.textPrimary)
        view.selectedTextAttributes = [.backgroundColor: NSColor(Theme.hairline)]
        view.textContainerInset = NSSize(width: 12, height: 8)
        view.typingAttributes = [.font: Self.font, .foregroundColor: NSColor(Theme.textPrimary)]
        view.placeholder = placeholder
        view.delegate = context.coordinator
        scroll.documentView = view
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = context.coordinator.view else { return }
        context.coordinator.parent = self
        if view.string != text {
            view.string = text
            Coordinator.highlight(view)
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Keeps the binding in step with the text and colours it after each edit.
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditor
        weak var view: SQLTextView?
        var focusToken = 0

        /// Creates the coordinator for one editor.
        init(_ parent: SQLEditor) { self.parent = parent }

        /// Passes an edit to the binding and re-colours.
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? SQLTextView else { return }
            parent.text = view.string
            Self.highlight(view)
        }

        /// Applies token colours to the whole text.
        static func highlight(_ view: SQLTextView) {
            guard let storage = view.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.foregroundColor: NSColor(Theme.textPrimary), .font: SQLEditor.font], range: full)
            for span in SQLHighlighter.spans(in: storage.string) {
                storage.addAttribute(.foregroundColor, value: SQLHighlighter.color(span.token), range: span.range)
            }
            storage.endEditing()
            view.needsDisplay = true
        }
    }
}
