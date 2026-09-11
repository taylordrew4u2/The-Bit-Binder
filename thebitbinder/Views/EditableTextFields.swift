import SwiftUI

/// Stable identity while typing or removing rows, including duplicate strings.
struct EditableTextFields: View {
    @Binding var values: [String]
    var showsAddButton = true
    @State private var rows: [EditableTextRow] = []
    @FocusState private var focusedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                HStack(alignment: .top) {
                    TextField("What do you know?", text: Binding(
                        get: { rows.first(where: { $0.id == row.id })?.text ?? row.text },
                        set: { value in
                            guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
                            rows[index].text = value
                            values = rows.map(\.text)
                        }
                    ), axis: .vertical)
                    .focused($focusedID, equals: row.id)
                    .accessibilityLabel("Target detail")
                    Button {
                        if focusedID == row.id { focusedID = nil }
                        rows.removeAll { $0.id == row.id }
                        values = rows.map(\.text)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove detail")
                }
            }
            if showsAddButton {
                Button("Add another", systemImage: "plus.circle") {
                    let row = EditableTextRow(text: "")
                    rows.append(row)
                    values = rows.map(\.text)
                    focusedID = row.id
                }
            }
        }
        .onAppear { synchronize() }
        .onChange(of: values) { _, _ in synchronize() }
    }

    private func synchronize() {
        guard rows.map(\.text) != values else { return }
        rows = EditableTextRow.reconcile(values, with: rows)
        if let focusedID, !rows.contains(where: { $0.id == focusedID }) {
            self.focusedID = nil
        }
    }
}
