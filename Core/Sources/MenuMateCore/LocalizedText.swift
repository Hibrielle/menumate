import Foundation

/// User-authored translations, separate from stable action IDs and script arguments.
public enum LocalizedText {
    public static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    public static func resolve(_ fallback: String, translations: [String: String]?, language: String = language) -> String {
        guard let translations else { return fallback }
        let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
        var candidates = [normalized]
        // Common regional Chinese tags do not include their script explicitly.
        if ["zh-cn", "zh-sg"].contains(normalized) { candidates.append("zh-hans") }
        if ["zh-tw", "zh-hk", "zh-mo"].contains(normalized) { candidates.append("zh-hant") }
        var parts = normalized.split(separator: "-").map(String.init)
        while parts.count > 1 { parts.removeLast(); candidates.append(parts.joined(separator: "-")) }
        for candidate in candidates {
            for key in translations.keys.sorted() where key.replacingOccurrences(of: "_", with: "-").lowercased() == candidate {
                if let text = translations[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            }
        }
        return fallback
    }

    public static func catalogTranslations(_ key: String, bundle: Bundle) -> [String: String]? {
        var result: [String: String] = [:]
        for language in ["en", "zh-Hans"] {
            guard let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) else { continue }
            let value = localized.localizedString(forKey: key, value: nil, table: nil)
            if value != key { result[language] = value }
        }
        return result.isEmpty ? nil : result
    }

    /// Preserve explicit local overrides, including a deliberately removed translation.
    public static func merging(upstream: [String: String]?, previous: [String: String]?, local: [String: String]?) -> [String: String]? {
        var result = upstream ?? [:]
        for key in Set((previous ?? [:]).keys).union((local ?? [:]).keys) {
            if local?[key] != previous?[key] { result[key] = local?[key] }
        }
        return result.isEmpty ? nil : result
    }
}
