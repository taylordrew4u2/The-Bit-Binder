import Foundation

@main
struct ListOrderRegression {
    static func main() {
        let stored = ["unloaded", "a", "a", "b", "another-unloaded", "c"]
        let visible = ["a", "b", "c"]
        precondition(VisibleListOrder.removing(offsets: [1], visible: visible, stored: stored)
                     == ["unloaded", "a", "a", "another-unloaded", "c"])
        precondition(VisibleListOrder.moving(offsets: [2], to: 0, visible: visible, stored: stored)
                     == ["unloaded", "c", "a", "another-unloaded", "b"])
        precondition(VisibleListOrder.moving(offsets: [0, 1], to: 3, visible: visible, stored: stored)
                     == ["unloaded", "c", "a", "another-unloaded", "b"])
        precondition(VisibleListOrder.moving(offsets: [9], to: 0, visible: visible, stored: stored) == stored)
        precondition(VisibleListOrder.removing(offsets: [9], visible: visible, stored: stored) == stored)
        print("Set list identity regression checks passed")
    }
}
