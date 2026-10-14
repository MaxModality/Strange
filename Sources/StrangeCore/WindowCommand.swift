import Foundation
import CoreGraphics

public enum DisplayDirection: Sendable, Equatable {
    case left, right
}

public enum WindowCommand: Sendable, Equatable {
    case zone(WindowZone)
    case moveDisplay(DisplayDirection)

    public var label: String {
        switch self {
        case .zone(let zone): zone.rawValue
        case .moveDisplay(.left): "Previous display (whole)"
        case .moveDisplay(.right): "Next display (whole)"
        }
    }
}

public enum DisplayNavigationError: Error, Equatable, Sendable {
    case invalidSourceIndex
}

public enum DisplayNavigation {
    /// Cycle through displays from left to right, using Accessibility's top-left
    /// coordinates. Vertically aligned displays sort from top to bottom, with
    /// input order breaking identical-origin ties. The result is an input index.
    public static func destinationIndex(from sourceIndex: Int, direction: DisplayDirection,
                                        in displayFrames: [CGRect]) throws -> Int? {
        guard !displayFrames.isEmpty else { return nil }
        guard displayFrames.indices.contains(sourceIndex) else {
            throw DisplayNavigationError.invalidSourceIndex
        }
        for frame in displayFrames { try validate(frame) }

        let orderedIndices = displayFrames.indices.sorted { lhs, rhs in
            let left = displayFrames[lhs]
            let right = displayFrames[rhs]
            if left.minX != right.minX { return left.minX < right.minX }
            if left.minY != right.minY { return left.minY < right.minY }
            return lhs < rhs
        }
        // Membership was validated above, so the sorted indices contain source.
        guard let position = orderedIndices.firstIndex(of: sourceIndex) else {
            throw DisplayNavigationError.invalidSourceIndex
        }
        let destination: Int
        switch direction {
        case .left: destination = position == 0 ? orderedIndices.count - 1 : position - 1
        case .right: destination = position == orderedIndices.count - 1 ? 0 : position + 1
        }
        return orderedIndices[destination]
    }
}
