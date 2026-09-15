import SwiftUI
import AppKit
import UniformTypeIdentifiers
import MenuMateCore

/// A concrete example or a snapshot of a real Finder selection. Reading files happens
/// only when choosing or refreshing them, not once for every action in the sidebar.
struct MenuPreviewInput {
    var contextIndex = 0
    var imageType = "public.png"
    var fileType = "public.plain-text"
    var selectionCount = 1
    var urls: [URL] = []
    var realContext: ResolvedMatchContext?

    var context: SimContext { [SimContext.image, .file, .folder, .empty][contextIndex] }
    var resolved: ResolvedMatchContext {
        realContext ?? MenuPreviewVisibility.context(
            for: context,
            contentType: context == .image ? UTType(imageType) : context == .file ? UTType(fileType) : nil,
            selectionCount: selectionCount)
    }

    mutating func useExamples() {
        urls = []
        realContext = nil
    }

    mutating func select(_ urls: [URL]) {
        self.urls = urls
        realContext = RuleMatcher.resolve(context: .items(urls))
    }
}

struct MenuPreviewControls: View {
    @Binding var input: MenuPreviewInput

    private var exampleTypes: [(String, String)] {
        input.context == .image
            ? [("PNG", "public.png"), ("JPEG", "public.jpeg"), ("HEIC", "public.heic"), ("GIF", "com.compuserve.gif"), ("TIFF", "public.tiff")]
            : [("TXT", "public.plain-text"), ("PDF", "com.adobe.pdf"), ("MP4", "public.mpeg-4"), ("ZIP", "public.zip-archive"), ("App", "com.apple.application-bundle")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ContextSim(selection: Binding(
                get: { input.contextIndex },
                set: { input.contextIndex = $0; input.useExamples() }))
            if input.realContext != nil {
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "menu.previewRealCount"), input.urls.count))
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer(minLength: 0)
                    Button(String(localized: "menu.refresh")) { input.select(input.urls) }
                    Button(String(localized: "menu.previewUseExamples")) { input.useExamples() }
                }
                .buttonStyle(.borderless)
                Text(input.urls.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.system(size: 10.5))
                    .foregroundStyle(MMColor.label2)
                    .lineLimit(2)
                    .help(input.urls.map(\.path).joined(separator: "\n"))
            } else if input.context != .empty {
                HStack(spacing: 8) {
                    if input.context == .image || input.context == .file {
                        Picker(String(localized: "menu.previewExampleType"), selection: Binding(
                            get: { input.context == .image ? input.imageType : input.fileType },
                            set: { if input.context == .image { input.imageType = $0 } else { input.fileType = $0 } })) {
                            ForEach(exampleTypes, id: \.1) { item in Text(item.0).tag(item.1) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        .accessibilityLabel(String(localized: "menu.previewExampleType"))
                    }
                    Spacer(minLength: 0)
                    Stepper(value: $input.selectionCount, in: 1...999) {
                        Text(String(format: String(localized: "menu.previewExampleCount"), input.selectionCount))
                            .font(.system(size: 11.5))
                    }
                    .fixedSize()
                }
            }
            Button(action: chooseFiles) {
                Label(String(localized: "menu.previewChooseFiles"), systemImage: "doc.viewfinder")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5))
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = String(localized: "menu.previewChoosePrompt")
        panel.message = String(localized: "menu.previewChooseMessage")
        if panel.runModal() == .OK { input.select(panel.urls) }
    }
}

extension MatchResult {
    var previewMessage: String? {
        switch self {
        case .matched: return nil
        case .emptySelection: return String(localized: "menu.previewEmptySelection")
        case .unavailableItem: return String(localized: "menu.previewUnavailable")
        case .targetMismatch: return String(localized: "menu.previewTargetMismatch")
        case .typeMismatch: return String(localized: "menu.previewTypeMismatch")
        case .tooFew(let count): return String(format: String(localized: "menu.previewTooFew"), count)
        case .tooMany(let count): return String(format: String(localized: "menu.previewTooMany"), count)
        }
    }
}
