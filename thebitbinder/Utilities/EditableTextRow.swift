import Foundation

struct EditableTextRow: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    static func reconcile(_ values: [String], with existing: [Self]) -> [Self] {
        var remaining = existing
        return values.map { value in
            if let index = remaining.firstIndex(where: { $0.text == value }) {
                return remaining.remove(at: index)
            }
            return Self(text: value)
        }
    }
}
