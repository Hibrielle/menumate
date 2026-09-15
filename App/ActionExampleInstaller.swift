import Foundation
import MenuMateCore

enum ActionExampleInstaller {
    static func makeImageAction(sortOrder: Int) throws -> MenuAction {
        let root = AppPaths.configDirectory().appendingPathComponent("Interfaces")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            for ext in ["html", "zsh"] {
                guard let source = Bundle.main.url(forResource: "image-compress", withExtension: ext) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("image-compress.\(ext)"))
            }
            return MenuAction(id: UUID(), title: String(localized: "dialog.imageAction"),
                              icon: .symbol("photo"), kind: .runScript(ScriptSpec(scriptPath: root.appendingPathComponent("image-compress.zsh").path)),
                              matching: MatchRule(targets: .files, utis: ["public.jpeg"]),
                              placement: .topLevel, isEnabled: false, sortOrder: sortOrder,
                              interface: ActionInterface(entry: root.appendingPathComponent("image-compress.html").path),
                              localizedTitles: LocalizedText.catalogTranslations("dialog.imageAction", bundle: .main))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
}
