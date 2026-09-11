import Foundation

@main
struct EditableRowsRegression {
    static func main() {
        var rows = [EditableTextRow(text: "same"), EditableTextRow(text: "same"), EditableTextRow(text: "third")]
        let firstID = rows[0].id
        let secondID = rows[1].id
        let thirdID = rows[2].id
        precondition(firstID != secondID, "Duplicate text needs distinct row IDs")
        rows[1].text = "edited"
        precondition(rows[1].id == secondID, "Typing must preserve field identity")
        rows.removeFirst()
        precondition(rows[0].id == secondID && rows[1].id == thirdID,
                     "Deleting an earlier row must not redirect a field's binding")
        let reconciled = EditableTextRow.reconcile(["new", "third", "edited"], with: rows)
        precondition(reconciled[1].id == thirdID && reconciled[2].id == secondID)
        print("Editable row identity regression checks passed")
    }
}
