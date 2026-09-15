import SwiftUI

/// Base title stays editable separately; empty translations fall back to it.
struct ActionTitleLocalizations: View {
    @Binding var translations: [String: String]?
    var body: some View {
        DisclosureGroup(String(localized: "editor.localizedTitles")) {
            VStack(alignment: .leading, spacing: 8) {
                field("en", label: String(localized: "editor.languageEnglish"))
                field("zh-Hans", label: String(localized: "editor.languageChinese"))
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func field(_ language: String, label: String) -> some View {
        PvField(label) {
            MMField(Binding(get: { translations?[language] ?? "" }, set: { value in
                var updated = translations ?? [:]
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { updated.removeValue(forKey: language) }
                else { updated[language] = value }
                translations = updated.isEmpty ? nil : updated
            }), placeholder: String(localized: "editor.translationFallback"), width: 200)
        }
    }
}
