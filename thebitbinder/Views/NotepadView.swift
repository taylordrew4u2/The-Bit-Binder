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
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                if notepadText.isEmpty {
                    Text("Jot down premises, bits, tags, and to-dos…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(LinedNotepadEditor.lineSpacing)
                        .padding(.horizontal, LinedNotepadEditor.horizontalInset)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    static let horizontalInset: CGFloat = 20
    static let topInset: CGFloat = 12
    static let lineSpacing: CGFloat = 8

    private func font(compatibleWith traits: UITraitCollection) -> UIFont {
        let effectiveTraits = UITraitCollection(traitsFrom: [
            traits,
            UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        ])
        return UIFont.preferredFont(forTextStyle: .body, compatibleWith: effectiveTraits)
    }

    func makeUIView(context: Context) -> RuledTextView {
        let tv = RuledTextView()
        // SwiftUI's effective size drives all metrics together, including custom
        // app sizes. UIKit must not independently change just the font.
        tv.adjustsFontForContentSizeCategory = false
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.ruleColor = UIColor.separator.withAlphaComponent(0.6)
        tv.textContainerInset = UIEdgeInsets(top: Self.topInset, left: Self.horizontalInset,
                                             bottom: Self.topInset, right: Self.horizontalInset)
        tv.textContainer.lineFragmentPadding = 0
        tv.text = text
        context.coordinator.applyTypography(to: tv)
        tv.delegate = context.coordinator
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        return tv
    }

    func updateUIView(_ tv: RuledTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronizeText(in: tv)
        context.coordinator.applyTypography(to: tv)
        if isFocused.wrappedValue, !tv.isFirstResponder {
            tv.becomeFirstResponder()
        } else if !isFocused.wrappedValue, tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private static func textAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
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
        var parent: LinedNotepadEditor
        private var appliedFont: UIFont?
        private var isUpdatingView = false

        init(_ parent: LinedNotepadEditor) { self.parent = parent }

        func synchronizeText(in textView: RuledTextView) {
            // Never replace provisional input from an IME with a binding echo
            // or a cloud update while composition is in progress.
            guard !isUpdatingView, textView.markedTextRange == nil,
                  textView.text != parent.text else { return }
            isUpdatingView = true
            defer { isUpdatingView = false }

            let selection = textView.selectedRange
            let font = parent.font(compatibleWith: textView.traitCollection)
            let attributes = LinedNotepadEditor.textAttributes(font: font)
            textView.attributedText = NSAttributedString(string: parent.text, attributes: attributes)
            restoreSelection(selection, in: textView)
            textView.typingAttributes = attributes
            textView.setNeedsDisplay()
        }

        func applyTypography(to textView: RuledTextView) {
            // Defer formatting until marked text is committed. Delegate callbacks
            // retry this even if SwiftUI has no further update to deliver.
            guard !isUpdatingView, textView.markedTextRange == nil else { return }
            let font = parent.font(compatibleWith: textView.traitCollection)
            guard appliedFont != font else { return }
            isUpdatingView = true
            let undoManager = textView.undoManager
            let wasUndoRegistrationEnabled = undoManager?.isUndoRegistrationEnabled == true
            if wasUndoRegistrationEnabled { undoManager?.disableUndoRegistration() }
            defer {
                if wasUndoRegistrationEnabled { undoManager?.enableUndoRegistration() }
                isUpdatingView = false
            }

            let selection = textView.selectedRange
            let attributes = LinedNotepadEditor.textAttributes(font: font)
            textView.font = font
            // Change attributes in place: a size preference must not replace
            // characters, write the synced binding, or reset the user's selection.
            textView.textStorage.beginEditing()
            textView.textStorage.addAttributes(
                attributes,
                range: NSRange(location: 0, length: textView.textStorage.length)
            )
            textView.textStorage.endEditing()
            restoreSelection(selection, in: textView)
            textView.typingAttributes = attributes
            textView.rowHeight = ceil(font.lineHeight) + LinedNotepadEditor.lineSpacing
            appliedFont = font
            textView.setNeedsLayout()
            textView.setNeedsDisplay()
        }

        private func restoreSelection(_ selection: NSRange, in textView: UITextView) {
            guard selection.location != NSNotFound else { return }
            let length = textView.textStorage.length
            let location = min(selection.location, length)
            textView.selectedRange = NSRange(
                location: location,
                length: min(selection.length, length - location)
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingView else { return }
            if parent.text != textView.text {
                parent.text = textView.text
            }
            if let ruledTextView = textView as? RuledTextView {
                applyTypography(to: ruledTextView)
            }
            textView.setNeedsDisplay()   // redraw rules as content grows
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let ruledTextView = textView as? RuledTextView else { return }
            applyTypography(to: ruledTextView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if let ruledTextView = textView as? RuledTextView {
                applyTypography(to: ruledTextView)
            }
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
