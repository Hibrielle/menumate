import Foundation
import UniformTypeIdentifiers

public enum MatchContext {
    case items([URL])
    case container(URL)
}

/// A Finder selection item after resolving filesystem metadata once.
/// Packages, including .app bundles, count as files rather than navigable folders.
public struct MatchItem: Equatable, Sendable {
    public let isDirectory: Bool
    public let contentType: UTType?
    public let isAvailable: Bool

    public init(isDirectory: Bool, contentType: UTType?) {
        self.isDirectory = isDirectory
        self.contentType = contentType
        self.isAvailable = true
    }

    private init() {
        self.isDirectory = false
        self.contentType = nil
        self.isAvailable = false
    }

    fileprivate static let unavailable = MatchItem()
}

public enum ResolvedMatchContext: Equatable, Sendable {
    case items([MatchItem])
    case container
}

public enum MatchResult: Equatable, Sendable {
    case matched
    case emptySelection
    case unavailableItem
    case targetMismatch
    case typeMismatch
    /// Associated values are the rule's required minimum or maximum.
    case tooFew(Int)
    case tooMany(Int)
}

public enum RuleMatcher {
    public static func visibleActions(in config: MenuConfig, context: MatchContext) -> [MenuAction] {
        let resolved = resolve(context: context)
        return config.actions
            .filter { $0.isEnabled && evaluate(rule: $0.matching, context: resolved) == .matched }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public static func matches(rule: MatchRule, context: MatchContext) -> Bool {
        evaluate(rule: rule, context: resolve(context: context)) == .matched
    }

    public static func resolve(context: MatchContext) -> ResolvedMatchContext {
        switch context {
        case .items(let urls):
            return .items(urls.map(resolveItem))
        case .container(let url):
            let item = resolveItem(url)
            // A missing path, ordinary file, or package cannot be a Finder background.
            guard item.isAvailable, item.isDirectory else { return .items([.unavailable]) }
            return .container
        }
    }

    /// Pure matching shared by real Finder selections and explicit preview examples.
    /// Every selected item must satisfy the target and one of the allowed UTI types.
    public static func evaluate(rule: MatchRule, context: ResolvedMatchContext) -> MatchResult {
        switch context {
        case .container:
            return rule.targets == .container ? .matched : .targetMismatch
        case .items(let items):
            guard !items.isEmpty else { return .emptySelection }
            guard items.allSatisfy(\.isAvailable) else { return .unavailableItem }
            guard rule.targets != .container else { return .targetMismatch }
            if let min = rule.minSelectionCount, items.count < min { return .tooFew(min) }
            if let max = rule.maxSelectionCount, items.count > max { return .tooMany(max) }

            let allowedTypes = rule.utis.compactMap { UTType($0) }
            for item in items {
                switch rule.targets {
                case .files where item.isDirectory, .folders where !item.isDirectory:
                    return .targetMismatch
                default:
                    break
                }
                if !rule.utis.isEmpty {
                    guard let type = item.contentType,
                          allowedTypes.contains(where: { type.conforms(to: $0) }) else {
                        return .typeMismatch
                    }
                }
            }
            return .matched
        }
    }

    private static func resolveItem(_ url: URL) -> MatchItem {
        guard url.isFileURL else { return .unavailable }
        // Finder can reuse URLs whose resource values were cached before a file changed.
        // Match the target's metadata but preserve the selected link URL for execution.
        var freshURL = url.resolvingSymlinksInPath()
        freshURL.removeAllCachedResourceValues()
        guard FileManager.default.fileExists(atPath: freshURL.path) else { return .unavailable }
        let values = try? freshURL.resourceValues(forKeys: [.contentTypeKey, .isDirectoryKey, .isPackageKey])
        let isDirectory: Bool
        if let directory = values?.isDirectory {
            isDirectory = directory
        } else {
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: freshURL.path, isDirectory: &directory) else {
                return .unavailable
            }
            isDirectory = directory.boolValue
        }

        let extensionType = UTType(filenameExtension: freshURL.pathExtension)
        let isPackage = values?.isPackage ?? (isDirectory && extensionType?.conforms(to: .package) == true)
        let finderDirectory = isDirectory && !isPackage
        let type = values?.contentType ?? (finderDirectory ? .folder : extensionType)
        return MatchItem(isDirectory: finderDirectory, contentType: type)
    }
}
