import Foundation

/// Translate visible row gestures without deleting records still awaiting sync.
enum VisibleListOrder {
    static func removing<ID: Hashable>(offsets: IndexSet, visible: [ID], stored: [ID]) -> [ID] {
        let removed = Set(offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil })
        return stored.filter { !removed.contains($0) }
    }

    static func moving<ID: Hashable>(offsets: IndexSet, to destination: Int, visible: [ID], stored: [ID]) -> [ID] {
        let valid = offsets.filter { visible.indices.contains($0) }
        guard !valid.isEmpty, (0...visible.count).contains(destination) else { return stored }
        let selected = valid.map { visible[$0] }
        let selectedOffsets = Set(valid)
        var reordered = visible.enumerated().filter { !selectedOffsets.contains($0.offset) }.map(\.element)
        let insertion = destination - valid.filter { $0 < destination }.count
        reordered.insert(contentsOf: selected, at: insertion)
        let visibleIDs = Set(visible)
        var seen = Set<ID>()
        var iterator = reordered.makeIterator()
        return stored.compactMap { id in
            guard visibleIDs.contains(id) else { return id }
            guard seen.insert(id).inserted else { return nil }
            return iterator.next()
        }
    }
}
