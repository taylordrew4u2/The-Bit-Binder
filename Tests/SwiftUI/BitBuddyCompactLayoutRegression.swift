import CoreGraphics

@main
struct BitBuddyCompactLayoutRegression {
    static func main() {
        let phone = BitBuddyCompactLayout(containerSize: CGSize(width: 390, height: 700))
        precondition(!phone.isExpanded)
        precondition(phone.panelSize == CGSize(width: 300, height: 380))
        precondition(phone.origin(for: .bottomTrailing, isRightToLeft: false) == CGPoint(x: 76, y: 306))
        precondition(phone.origin(for: .bottomTrailing, isRightToLeft: true) == CGPoint(x: 14, y: 306))

        // Compact chrome cannot fit on a narrow phone, in landscape, or above
        // a tall keyboard. Each case gets the whole available safe-area region.
        for size in [CGSize(width: 320, height: 568), CGSize(width: 700, height: 300), CGSize(width: 390, height: 280)] {
            let layout = BitBuddyCompactLayout(containerSize: size)
            precondition(layout.isExpanded)
            precondition(layout.panelSize == size)
            for corner in BitBuddyCompactLayout.Corner.allCases {
                precondition(layout.origin(for: corner, isRightToLeft: false) == .zero)
                precondition(layout.constrainedOffset(CGSize(width: 80, height: -90), from: .zero) == .zero)
            }
        }

        let accessible = BitBuddyCompactLayout(containerSize: phone.containerSize, needsExpandedLayout: true)
        precondition(accessible.isExpanded)
        precondition(accessible.panelSize == phone.containerSize)

        // A dragged panel must never move its close button beyond usable bounds.
        for corner in BitBuddyCompactLayout.Corner.allCases {
            for rtl in [false, true] {
                let origin = phone.origin(for: corner, isRightToLeft: rtl)
                for dx in [-1000.0, 0, 1000] {
                    for dy in [-1000.0, 0, 1000] {
                        let offset = phone.constrainedOffset(CGSize(width: dx, height: dy), from: origin)
                        let frame = CGRect(origin: CGPoint(x: origin.x + offset.width, y: origin.y + offset.height), size: phone.panelSize)
                        precondition(frame.minX >= phone.inset && frame.maxX <= phone.containerSize.width - phone.inset)
                        precondition(frame.minY >= phone.inset && frame.maxY <= phone.containerSize.height - phone.inset)
                    }
                }
                let center = CGPoint(x: origin.x + phone.panelSize.width / 2, y: origin.y + phone.panelSize.height / 2)
                precondition(phone.nearestCorner(to: center, isRightToLeft: rtl) == corner)
            }
        }

        // Corner resolution is in overlay coordinates, independent of its
        // position on screen; semantic leading/trailing also handles RTL.
        precondition(phone.nearestCorner(to: CGPoint(x: 10, y: 10), isRightToLeft: false) == .topLeading)
        precondition(phone.nearestCorner(to: CGPoint(x: 10, y: 10), isRightToLeft: true) == .topTrailing)
        precondition(phone.nearestCorner(to: CGPoint(x: 380, y: 690), isRightToLeft: false) == .bottomTrailing)
        precondition(phone.nearestCorner(to: CGPoint(x: 380, y: 690), isRightToLeft: true) == .bottomLeading)

        for size in [CGSize.zero, CGSize(width: -1, height: -1), CGSize(width: CGFloat.infinity, height: CGFloat.nan)] {
            let layout = BitBuddyCompactLayout(containerSize: size)
            precondition(layout.panelSize == .zero)
            precondition(layout.origin(for: .bottomTrailing, isRightToLeft: false) == .zero)
        }
        print("BitBuddy compact layout regression checks passed")
    }
}
