import CoreGraphics

/// Geometry shared by the compact chat and its drag handling. All coordinates
/// are relative to the overlay's usable (including keyboard-safe) bounds.
struct BitBuddyCompactLayout {
    enum Corner: String, CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    let containerSize: CGSize
    let panelSize: CGSize
    let inset: CGFloat
    let isExpanded: Bool

    init(containerSize: CGSize, needsExpandedLayout: Bool = false) {
        let width = Self.validDimension(containerSize.width)
        let height = Self.validDimension(containerSize.height)
        self.containerSize = CGSize(width: width, height: height)

        // Use the whole usable region if compact chrome would leave too
        // little room for the conversation and composer. This also avoids
        // replacing the chat (and losing its draft/focus) when the keyboard opens.
        isExpanded = needsExpandedLayout || width < 328 || height < 408
        inset = isExpanded ? 0 : 14
        panelSize = isExpanded
            ? self.containerSize
            : CGSize(width: min(300, width - 2 * inset), height: min(380, height - 2 * inset))
    }

    func origin(for corner: Corner, isRightToLeft: Bool) -> CGPoint {
        let leading = corner == .topLeading || corner == .bottomLeading
        let top = corner == .topLeading || corner == .topTrailing
        let left = leading != isRightToLeft
        return CGPoint(
            x: left ? inset : containerSize.width - panelSize.width - inset,
            y: top ? inset : containerSize.height - panelSize.height - inset
        )
    }

    func constrainedOffset(_ offset: CGSize, from origin: CGPoint) -> CGSize {
        let maxX = max(inset, containerSize.width - panelSize.width - inset)
        let maxY = max(inset, containerSize.height - panelSize.height - inset)
        return CGSize(
            width: min(max(inset, origin.x + offset.width), maxX) - origin.x,
            height: min(max(inset, origin.y + offset.height), maxY) - origin.y
        )
    }

    func nearestCorner(to point: CGPoint, isRightToLeft: Bool) -> Corner {
        let top = point.y < containerSize.height / 2
        let leading = (point.x < containerSize.width / 2) != isRightToLeft
        switch (top, leading) {
        case (true, true): return .topLeading
        case (true, false): return .topTrailing
        case (false, true): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }

    private static func validDimension(_ dimension: CGFloat) -> CGFloat {
        dimension.isFinite ? max(0, dimension) : 0
    }
}
