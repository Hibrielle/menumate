import AppKit
import WebKit
import MenuMateCore

/// Each window owns an immutable action and Finder selection. The page can submit
/// parameters for that action once; it cannot name a different script or action.
@MainActor
final class ActionWindowController: NSWindowController, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    private static var sessions: [UUID: ActionWindowController] = [:]
    private let sessionID = UUID()
    private let action: MenuAction
    private let urls: [URL]
    private let variant: String?
    private let workspace: TestWorkspace?
    private let entry: URL
    private let webView: WKWebView
    private let status = NSTextField(wrappingLabelWithString: "")
    private let closeButton = NSButton()
    private var completion: ((ShellResult?) -> Void)?
    private var submitted = false
    private var running = false
    private var closed = false

    static func present(action: MenuAction, variant: String?, urls: [URL], workspace: TestWorkspace? = nil,
                        completion: ((ShellResult?) -> Void)? = nil) {
        do {
            guard !AppState.shared.storageRecoveryRequired else { throw PackTransaction.Failure.pendingRecovery }
            let controller = try ActionWindowController(action: action, variant: variant, urls: urls,
                                                        workspace: workspace, completion: completion)
            PackUsage.retain(action.packID)
            sessions[controller.sessionID] = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            controller.loadPage()
        } catch {
            let result = ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
            if let completion { completion(result) }
            else { Notifier.showFailure(action.displayTitle, error.localizedDescription) }
        }
    }

    private init(action: MenuAction, variant: String?, urls: [URL], workspace: TestWorkspace?,
                 completion: ((ShellResult?) -> Void)?) throws {
        guard let spec = action.interface else { throw CocoaError(.fileNoSuchFile) }
        let entry = spec.resolvedURL(base: AppPaths.configDirectory()).resolvingSymlinksInPath()
        guard entry.isFileURL, ["html", "htm"].contains(entry.pathExtension.lowercased()),
              FileManager.default.isReadableFile(atPath: entry.path),
              (try entry.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576
        else { throw CocoaError(.fileReadInvalidFileName) }
        self.action = action; self.variant = variant; self.urls = urls
        self.workspace = workspace; self.completion = completion; self.entry = entry
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(900, max(360, spec.width)),
                                                  height: min(900, max(320, spec.height))),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = action.displayTitle + (workspace == nil ? "" : " · " + String(localized: "test.title"))
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 320)
        let content = NSView()
        window.contentView = content
        webView.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = String(localized: workspace == nil ? "dialog.waiting" : "dialog.testWaiting")
        closeButton.title = String(localized: "editor.cancel")
        closeButton.bezelStyle = .rounded
        closeButton.target = self; closeButton.action = #selector(closeRequested)
        content.addSubview(webView); content.addSubview(status); content.addSubview(closeButton)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: content.topAnchor),
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            status.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: status.centerYAnchor)
        ])
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "menumate")
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private var preferencesKey: String { "actionParameters.\(action.id.uuidString)" }

    private func loadPage() {
        let remembered = workspace == nil ? UserDefaults.standard.string(forKey: preferencesKey) : nil
        let context: [String: Any] = [
            "runID": sessionID.uuidString, "title": action.displayTitle,
            "locale": Bundle.main.preferredLocalizations.first ?? "en",
            "files": urls.map { ["name": $0.lastPathComponent, "path": $0.path] },
            "variant": variant ?? "", "isTestRun": workspace != nil,
            "testRoot": workspace?.directory.path ?? "",
            "parameters": remembered.flatMap { try? ActionParameters.decode($0) } ?? [:]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: context),
              let jsonLiteral = try? JSONSerialization.data(withJSONObject: String(decoding: data, as: UTF8.self), options: .fragmentsAllowed)
        else { return }
        let source = """
        (() => {
          const context = JSON.parse(\(String(decoding: jsonLiteral, as: UTF8.self)));
          window.menumate = Object.freeze({
            context,
            submit(parameters, remember = false) {
              window.webkit.messageHandlers.menumate.postMessage({type:'submit', runID:context.runID, parameters, remember});
            },
            cancel() { window.webkit.messageHandlers.menumate.postMessage({type:'cancel', runID:context.runID}); }
          });
        })();
        """
        webView.configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Local packages are reviewed as installed. Remote scripts/resources must
        // not replace that reviewed page at runtime.
        let rules = ActionInterface.localContentRules
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "MenuMateLocalActions", encodedContentRuleList: rules) { [weak self] list, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                guard let list else {
                    self.status.stringValue = String(localized: "dialog.loadFailed")
                    if let error {
                        NSLog("MenuMate local page rule compilation failed: %@", String(describing: error as NSError))
                    }
                    return
                }
                self.webView.configuration.userContentController.add(list)
                self.webView.loadFileURL(self.entry, allowingReadAccessTo: self.entry.deletingLastPathComponent())
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed, message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.resolvingSymlinksInPath().path == entry.path,
              let body = message.body as? [String: Any],
              body["runID"] as? String == sessionID.uuidString else { return }
        switch body["type"] as? String {
        case "cancel":
            if !running { close() }
        case "submit":
            guard !submitted else { return }
            do {
                let parameters = try ActionParameters.encode(body["parameters"] ?? [:])
                let context: MatchContext = action.matching.targets == .container
                    ? .container(urls.first ?? URL(fileURLWithPath: "/nonexistent")) : .items(urls)
                guard RuleMatcher.matches(rule: action.matching, context: context) else {
                    status.stringValue = String(localized: "test.changedSamples")
                    return
                }
                submitted = true; running = true; closeButton.isEnabled = false
                status.stringValue = String(localized: "dialog.running")
                if body["remember"] as? Bool == true, workspace == nil {
                    UserDefaults.standard.set(parameters, forKey: preferencesKey)
                }
                var environment = workspace?.environment ?? [:]
                environment["MENUMATE_INPUT"] = parameters
                ActionRunner().runWithResult(action: action, variant: variant, urls: urls,
                                             environment: environment, cwdOverride: workspace?.workingDirectory,
                                             recordExecution: workspace == nil) { [weak self] result in
                    guard let self else { return }
                    self.running = false; self.closeButton.isEnabled = true
                    self.closeButton.title = String(localized: "editor.testRunClose")
                    self.status.stringValue = result.timedOut ? String(localized: "editor.testRunTimedOut")
                        : result.exitCode == 0 ? String(localized: "dialog.succeeded")
                        : "exit \(result.exitCode): \(String(result.stderr.prefix(300)))"
                    self.completion?(result); self.completion = nil
                    self.sendResult(result)
                }
            } catch { status.stringValue = String(localized: "dialog.invalidParameters") }
        default: break
        }
    }

    private func sendResult(_ result: ShellResult) {
        let payload: [String: Any] = ["exitCode": result.exitCode, "stdout": String(result.stdout.prefix(32000)),
                                     "stderr": String(result.stderr.prefix(32000)), "timedOut": result.timedOut]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('menumate:result', {detail:\(String(decoding: data, as: UTF8.self))}));", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // No subframes, popups or navigation to another document.
        let target = navigationAction.request.url?.resolvingSymlinksInPath()
        decisionHandler(navigationAction.targetFrame?.isMainFrame == true &&
                        target?.isFileURL == true && target?.path == entry.path ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status.stringValue = error.localizedDescription
    }

    @objc private func closeRequested() { if !running { close() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !running }
    func windowWillClose(_ notification: Notification) {
        closed = true
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "menumate")
        webView.configuration.userContentController.removeAllUserScripts()
        completion?(nil); completion = nil
        PackUsage.release(action.packID)
        Self.sessions.removeValue(forKey: sessionID)
    }
}
