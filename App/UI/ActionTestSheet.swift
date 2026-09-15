import SwiftUI
import AppKit
import MenuMateCore

@MainActor
private final class ActionTestModel: ObservableObject {
    let action: MenuAction
    @Published var resource: TestResource
    @Published var count: Int
    @Published var variant = ""
    @Published var workspace: TestWorkspace?
    @Published var result: ShellResult?
    @Published var error: String?
    @Published var preparing = false
    @Published var running = false

    init(action: MenuAction) {
        self.action = action
        let resources = TestResource.matching(action.matching)
        resource = action.matching.utis.isEmpty && resources.contains(.text) ? .text : resources.first ?? .text
        count = min(20, max(1, action.matching.minSelectionCount ?? 1))
    }

    var variants: [String] {
        switch action.variants {
        case .fixed(let values): return values
        case .directoryListing: return (try? workspace?.variants(for: action)) ?? []
        case nil: return []
        }
    }

    func prepare() {
        guard !preparing, !running else { return }
        preparing = true; error = nil; result = nil; workspace = nil
        let action = action, resource = resource, count = count
        Task {
            do {
                let prepared = try await Task.detached {
                    try TestWorkspace.create(action: action, resource: resource, count: count)
                }.value
                workspace = prepared
                variant = variants.first ?? ""
            } catch { self.error = error.localizedDescription }
            preparing = false
        }
    }

    func run() {
        guard let workspace, !running, !preparing else { return }
        let context: MatchContext = action.matching.targets == .container
            ? .container(workspace.workingDirectory) : .items(workspace.inputs)
        guard RuleMatcher.matches(rule: action.matching, context: context) else {
            error = String(localized: "test.changedSamples")
            return
        }
        if action.variants != nil, !variants.contains(variant) {
            error = String(localized: "test.changedSamples")
            return
        }
        if case .runScript(let spec) = action.kind,
           spec.scriptPath == nil && (spec.inlineSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = String(localized: "editor.testRunNoScript"); return
        }
        running = true; error = nil; result = nil
        let selectedVariant = action.variants == nil ? nil : variant
        if action.interface != nil {
            ActionWindowController.present(action: action, variant: selectedVariant, urls: workspace.inputs,
                                           workspace: workspace) { [weak self] result in
                self?.result = result
                self?.running = false
            }
        } else {
            ActionRunner().runWithResult(action: action, variant: selectedVariant, urls: workspace.inputs,
                                         environment: workspace.environment, cwdOverride: workspace.workingDirectory,
                                         recordExecution: false) { [weak self] result in
                self?.result = result
                self?.running = false
            }
        }
    }
}

struct ActionTestSheet: View {
    @StateObject private var model: ActionTestModel
    @Environment(\.dismiss) private var dismiss

    init(action: MenuAction) { _model = StateObject(wrappedValue: ActionTestModel(action: action)) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "testtube.2").foregroundStyle(MMColor.accent)
                    Text(String(localized: "test.title")).font(.headline)
                    Spacer()
                    Text(model.action.displayTitle).foregroundStyle(MMColor.label2).lineLimit(1)
                }
                Text(String(localized: "test.description"))
                    .font(.system(size: 12)).foregroundStyle(MMColor.label2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Picker(String(localized: "test.resource"), selection: $model.resource) {
                        ForEach(TestResource.matching(model.action.matching), id: \.self) { resource in
                            Text(resource.label).tag(resource)
                        }
                    }
                    .frame(width: 170)
                    if model.action.matching.targets != .container {
                        Stepper(String(format: String(localized: "menu.previewExampleCount"), model.count),
                                value: $model.count, in: 1...20)
                    }
                    Spacer(minLength: 0)
                    Button(String(localized: "test.prepare")) { model.prepare() }
                }
                .disabled(model.preparing || model.running)
                .onChange(of: model.resource) { _ in model.workspace = nil; model.result = nil }
                .onChange(of: model.count) { _ in model.workspace = nil; model.result = nil }
                if model.preparing {
                    ProgressView(String(localized: "test.preparing")).controlSize(.small)
                }
                if let workspace = model.workspace {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(MMColor.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workspace.directory.path)
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(workspace.inputs.map(\.lastPathComponent).joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(MMColor.label2)
                        }
                        Spacer(minLength: 0)
                        Button(String(localized: "test.openFolder")) { NSWorkspace.shared.open(workspace.directory) }
                            .fixedSize()
                    }
                    if model.action.variants != nil {
                        Picker(String(localized: "editor.testRunVariant"), selection: $model.variant) {
                            ForEach(model.variants, id: \.self) { Text($0).tag($0) }
                        }.disabled(model.running)
                    }
                }
                if let error = model.error { Banner(error, tone: .red) }
                if let result = model.result {
                    Label(result.timedOut ? String(localized: "editor.testRunTimedOut")
                          : String(format: String(localized: result.exitCode == 0 ? "editor.testRunSuccess" : "editor.testRunFailed"), Int(result.exitCode)),
                          systemImage: result.exitCode == 0 && !result.timedOut ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.exitCode == 0 && !result.timedOut ? MMColor.green : MMColor.red)
                    ScrollView {
                        Text([result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 180)
                    .padding(10).background(MMColor.field, in: RoundedRectangle(cornerRadius: 6))
                }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MMActionBar {
                HStack {
                    if model.running { ProgressView(String(localized: "test.running")).controlSize(.small) }
                    Spacer()
                    MMButton(String(localized: "editor.testRunClose")) { dismiss() }
                        .disabled(model.running || model.preparing)
                    MMButton(String(localized: "test.run"), systemImage: "play", kind: .primary) { model.run() }
                        .disabled(model.workspace == nil || model.running || model.preparing ||
                                  (model.action.variants != nil && model.variants.isEmpty))
                }
            }
        }
        .frame(width: 580, height: 500)
        .interactiveDismissDisabled(model.running || model.preparing)
        .task { model.prepare() }
    }
}
