//
//  NotepadView.swift
//  thebitbinder
//
//  A single, always-present scrollable notepad. One freeform text area for
//  jotting notes — no separate note objects. Backed by the iCloud-synced
//  `notepadText` key so the same notepad follows the user across devices.
//

import SwiftUI

struct NotepadView: View {
    @AppStorage("notepadText") private var notepadText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $notepadText)
            .font(.body)
            .lineSpacing(6)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .focused($isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .readableWidth(DS.wideContentWidth)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                if notepadText.isEmpty {
                    Text("Jot down premises, bits, tags, and to-dos…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, DS.Spacing.lg + 5)
                        .padding(.vertical, DS.Spacing.md + 8)
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
