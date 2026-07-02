//
//  NotepadView.swift
//  thebitbinder
//
//  A single, always-present scrollable notepad drawn on ruled "lined paper".
//  One freeform text area for jotting notes — no separate note objects. Backed
//  by the iCloud-synced `notepadText` key so the same notepad follows the user
//  across devices.
//

import SwiftUI
import UIKit

struct NotepadView: View {
    @AppStorage("notepadText") private var notepadText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LinedNotepadEditor(text: $notepadText, isFocused: $isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readableWidth(DS.wideContentWidth)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                if notepadText.isEmpty {
                    Text("Jot down premises, bits, tags, and to-dos…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, LinedNotepadEditor.horizontalInset + 5)
                        .padding(.top, LinedNotepadEditor.topInset)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Notepad")
            .toolbar {
                if isFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isFocused = false }
                    }
                }
            }
    }
}

// MARK: - Lined UITextView wrapper

/// A UITextView that draws evenly-spaced horizontal rules behind the text.
/// The rules are drawn in content coordinates so they scroll with the text,
/// and the row height is matched to the font's line height plus spacing so
/// each line of text sits on a rule.
struct LinedNotepadEditor: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 12
    static let lineSpacing: CGFloat = 8

    private static var font: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    private static var rowHeight: CGFloat { ceil(font.lineHeight) + lineSpacing }

    func makeUIView(context: Context) -> RuledTextView {
        let tv = RuledTextView()
        tv.delegate = context.coordinator
        tv.font = Self.font
        tv.rowHeight = Self.rowHeight
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.ruleColor = UIColor.separator.withAlphaComponent(0.6)
        tv.textContainerInset = UIEdgeInsets(top: Self.topInset, left: Self.horizontalInset,
                                             bottom: Self.topInset, right: Self.horizontalInset)
        tv.textContainer.lineFragmentPadding = 0
        tv.typingAttributes = Self.textAttributes
        tv.text = text
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        return tv
    }

    func updateUIView(_ tv: RuledTextView, context: Context) {
        if tv.text != text {
            // Preserve attributes when replacing text pushed in from iCloud sync.
            tv.attributedText = NSAttributedString(string: text, attributes: Self.textAttributes)
            tv.setNeedsDisplay()
        }
        if isFocused.wrappedValue, !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFocused.wrappedValue, tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        // Pin the line height so text baselines line up with the drawn rules.
        paragraph.minimumLineHeight = ceil(font.lineHeight)
        paragraph.maximumLineHeight = ceil(font.lineHeight)
        return [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: LinedNotepadEditor
        init(_ parent: LinedNotepadEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.setNeedsDisplay()   // redraw rules as content grows
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = false
        }
    }
}

/// UITextView that paints horizontal ruled lines behind its text.
final class RuledTextView: UITextView {
    var rowHeight: CGFloat = 28 { didSet { setNeedsDisplay() } }
    var ruleColor: UIColor = .separator { didSet { setNeedsDisplay() } }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), rowHeight > 0 else {
            super.draw(rect)
            return
        }

        ctx.setStrokeColor(ruleColor.cgColor)
        ctx.setLineWidth(1.0 / (window?.screen.scale ?? UIScreen.main.scale))

        // Draw a rule at the bottom of every text row, across the full content
        // height, so the lines scroll with the text.
        let firstRuleY = textContainerInset.top + rowHeight
        let maxY = max(bounds.height, contentSize.height)
        var y = firstRuleY
        while y <= maxY {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: bounds.width, y: y))
            y += rowHeight
        }
        ctx.strokePath()

        super.draw(rect)
    }
}
