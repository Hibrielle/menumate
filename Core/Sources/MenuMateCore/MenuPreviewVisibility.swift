import Foundation
import UniformTypeIdentifiers

/// Preview objects are concrete examples, not a union of all types in a category.
public enum SimContext: String, CaseIterable, Sendable {
    case image    // PNG unless an explicit image type is supplied
    case file     // Plain text unless an explicit file type is supplied
    case folder
    case empty
}

public enum MenuPreviewVisibility {
    /// Builds the same resolved input used for real selections, without disk access.
    /// A count of zero produces an empty selection; Finder backgrounds have no selection.
    public static func context(for context: SimContext, contentType: UTType? = nil,
                               selectionCount: Int = 1) -> ResolvedMatchContext {
        let item: MatchItem
        switch context {
        case .image:
            item = MatchItem(isDirectory: false, contentType: contentType ?? .png)
        case .file:
            item = MatchItem(isDirectory: false, contentType: contentType ?? .plainText)
        case .folder:
            item = MatchItem(isDirectory: true, contentType: .folder)
        case .empty:
            return .container
        }
        return .items(Array(repeating: item, count: max(0, selectionCount)))
    }

    public static func isVisible(_ rule: MatchRule, in context: SimContext,
                                 selectionCount: Int = 1) -> Bool {
        RuleMatcher.evaluate(rule: rule, context: self.context(for: context, selectionCount: selectionCount)) == .matched
    }

    /// Enabled state is deliberately separate so disabled actions remain manageable.
    public static func isVisible(_ action: MenuAction, in context: SimContext,
                                 selectionCount: Int = 1) -> Bool {
        isVisible(action.matching, in: context, selectionCount: selectionCount)
    }
}
