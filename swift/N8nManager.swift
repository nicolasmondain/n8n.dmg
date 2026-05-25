// N8nManager.swift — Native macOS app wrapping n8n in a WKWebView
// The full n8n UI runs in a native window — no browser needed.
// Compiled with: swiftc -O -target arm64-apple-macosx12.0
// No Xcode project — just Command Line Tools.

import Cocoa
import WebKit
import Foundation

// MARK: - Process Helper (no shell interpretation)

/// Runs a command directly without going through /bin/bash -c.
/// All arguments are passed as an explicit array, eliminating shell injection risks.
@discardableResult
func run(_ executable: String, _ arguments: [String] = []) -> (output: String, exitCode: Int32) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return ("", -1)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, process.terminationStatus)
}

// MARK: - Service Manager

class ServiceManager {
    let installDir: String
    let launchAgentLabel = "com.n8n.local"
    let guiUID: uid_t

    init() {
        self.installDir = NSHomeDirectory() + "/.n8n-local"
        self.guiUID = getuid()
    }

    var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(launchAgentLabel).plist"
    }

    var logFile: String {
        installDir + "/logs/n8n.log"
    }

    func readPort() -> Int {
        let path = installDir + "/.port"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return 5678 }
        let port = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 5678
        guard port >= 1 && port <= 65535 else { return 5678 }
        return port
    }

    func readVersion() -> String {
        let path = installDir + "/.version"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return "unknown" }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only allow version-like characters (digits, dots, dashes, alphanumeric)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "unknown" }
        return trimmed
    }

    func isLoaded() -> Bool {
        let (_, exit) = run("/bin/launchctl", ["print", "gui/\(guiUID)/\(launchAgentLabel)"])
        return exit == 0
    }

    func getPid() -> Int {
        let (output, exit) = run("/bin/launchctl", ["print", "gui/\(guiUID)/\(launchAgentLabel)"])
        guard exit == 0 else { return 0 }
        guard let range = output.range(of: "pid = \\d+", options: .regularExpression) else { return 0 }
        let match = String(output[range])
        let parts = match.split(separator: " ")
        guard parts.count == 3, let pid = Int(parts[2]) else { return 0 }
        return pid
    }

    func isPortListening() -> Bool {
        let port = readPort()
        let (_, exit) = run("/usr/sbin/lsof", ["-i", ":\(port)", "-sTCP:LISTEN"])
        return exit == 0
    }

    func isReady() -> Bool {
        let port = readPort()
        let (_, exit) = run("/usr/bin/curl", ["-sf", "http://127.0.0.1:\(port)/healthz", "-o", "/dev/null"])
        return exit == 0
    }

    func start() {
        if !isLoaded() {
            _ = run("/bin/launchctl", ["bootstrap", "gui/\(guiUID)", plistPath])
        }
    }

    func stop() {
        if isLoaded() {
            _ = run("/bin/launchctl", ["bootout", "gui/\(guiUID)/\(launchAgentLabel)"])
        }
    }

    func readLogs(lines: Int = 200) -> String {
        guard FileManager.default.fileExists(atPath: logFile) else {
            return "(no log file found)"
        }
        let (output, _) = run("/usr/bin/tail", ["-n", "\(lines)", logFile])
        return output
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {

    let serviceManager = ServiceManager()
    var window: NSWindow!
    var webView: WKWebView!
    var loadingView: NSView!
    var loadingLabel: NSTextField!
    var spinner: NSProgressIndicator!
    var statusItem: NSTextField!
    var pollTimer: Timer?
    var startupTimer: Timer?
    var allowedPort: Int = 5678

    // Terminal panel
    var terminalPanel: TerminalPanelView?
    var terminalToggleButton: NSButton!
    var terminalVisible = false

    // n8n pink
    let n8nPink = NSColor(red: 0.918, green: 0.294, blue: 0.443, alpha: 1.0)

    func applicationDidFinishLaunching(_ notification: Notification) {
        allowedPort = serviceManager.readPort()
        setupMenuBar()
        buildWindow()
        ensureServiceRunning()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Menu bar

    func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About n8n", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit n8n", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Service menu
        let serviceMenuItem = NSMenuItem()
        let serviceMenu = NSMenu(title: "Service")
        serviceMenu.addItem(withTitle: "Start n8n", action: #selector(startService), keyEquivalent: "")
        serviceMenu.addItem(withTitle: "Stop n8n", action: #selector(stopService), keyEquivalent: "")
        serviceMenu.addItem(withTitle: "Restart n8n", action: #selector(restartService), keyEquivalent: "r")
        serviceMenu.addItem(NSMenuItem.separator())
        serviceMenu.addItem(withTitle: "View Logs", action: #selector(showLogs), keyEquivalent: "l")
        serviceMenuItem.submenu = serviceMenu
        mainMenu.addItem(serviceMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Terminal", action: #selector(toggleTerminal), keyEquivalent: "t")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Window

    func buildWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let windowWidth: CGFloat = min(1280, screenFrame.width * 0.85)
        let windowHeight: CGFloat = min(860, screenFrame.height * 0.85)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "n8n"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        window.titlebarAppearsTransparent = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        // Toolbar with status
        let toolbar = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 32, width: contentView.bounds.width, height: 32))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(toolbar)

        statusItem = NSTextField(labelWithString: "")
        statusItem.frame = NSRect(x: 10, y: 6, width: 300, height: 20)
        statusItem.font = NSFont.systemFont(ofSize: 12)
        statusItem.textColor = .secondaryLabelColor
        statusItem.autoresizingMask = [.maxXMargin]
        toolbar.addSubview(statusItem)

        // Separator
        let sep = NSBox(frame: NSRect(x: 0, y: 0, width: toolbar.bounds.width, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width]
        toolbar.addSubview(sep)

        // WebView
        let config = WKWebViewConfiguration()
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 32), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        contentView.addSubview(webView)

        // Terminal toggle button (bottom-right): a white circle with a terminal icon.
        let toggleSize: CGFloat = 40
        terminalToggleButton = CircleIconButton(frame: NSRect(x: 0, y: 0, width: toggleSize, height: toggleSize))
        terminalToggleButton.bezelStyle = .regularSquare
        terminalToggleButton.isBordered = false
        terminalToggleButton.title = "🖥️"
        terminalToggleButton.alignment = .center
        terminalToggleButton.font = NSFont.systemFont(ofSize: 17)
        terminalToggleButton.wantsLayer = true
        terminalToggleButton.layer?.backgroundColor = NSColor.white.cgColor
        terminalToggleButton.layer?.cornerRadius = toggleSize / 2
        terminalToggleButton.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
        terminalToggleButton.layer?.shadowOffset = NSSize(width: 0, height: -1)
        terminalToggleButton.layer?.shadowRadius = 4
        terminalToggleButton.layer?.shadowOpacity = 1
        terminalToggleButton.target = self
        terminalToggleButton.action = #selector(toggleTerminal)
        terminalToggleButton.toolTip = "Toggle Terminal (⌘T)"
        terminalToggleButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(terminalToggleButton)

        NSLayoutConstraint.activate([
            terminalToggleButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            terminalToggleButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            terminalToggleButton.widthAnchor.constraint(equalToConstant: toggleSize),
            terminalToggleButton.heightAnchor.constraint(equalToConstant: toggleSize)
        ])

        // Observe terminal panel close
        NotificationCenter.default.addObserver(self, selector: #selector(handleTerminalClose(_:)),
                                               name: NSNotification.Name("TerminalPanelClose"), object: nil)

        // Loading overlay
        loadingView = NSView(frame: contentView.bounds)
        loadingView.autoresizingMask = [.width, .height]
        loadingView.wantsLayer = true
        loadingView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(loadingView)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.sizeToFit()
        spinner.frame.origin = NSPoint(
            x: (loadingView.bounds.width - spinner.bounds.width) / 2,
            y: (loadingView.bounds.height - spinner.bounds.height) / 2 + 20
        )
        spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        spinner.startAnimation(nil)
        loadingView.addSubview(spinner)

        loadingLabel = NSTextField(labelWithString: "Starting n8n...")
        loadingLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.alignment = .center
        loadingLabel.sizeToFit()
        loadingLabel.frame.origin = NSPoint(
            x: (loadingView.bounds.width - loadingLabel.bounds.width) / 2,
            y: spinner.frame.origin.y - 40
        )
        loadingLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        loadingView.addSubview(loadingLabel)

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Service lifecycle

    func ensureServiceRunning() {
        updateStatus("Starting n8n...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.serviceManager.start()

            // Poll until n8n is ready (up to 60s)
            var attempts = 0
            while attempts < 60 {
                if self.serviceManager.isReady() {
                    DispatchQueue.main.async {
                        self.loadN8nUI()
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 1.0)
                attempts += 1
                DispatchQueue.main.async {
                    self.updateStatus("Starting n8n... (\(attempts)s)")
                }
            }

            DispatchQueue.main.async {
                self.updateStatus("n8n failed to start. Check Service > View Logs.")
                self.loadingLabel.stringValue = "n8n failed to start"
                self.spinner.stopAnimation(nil)
            }
        }
    }

    func loadN8nUI() {
        let port = serviceManager.readPort()
        guard let url = URL(string: "http://127.0.0.1:\(port)") else {
            updateStatus("Invalid port configuration")
            return
        }
        allowedPort = port
        webView.load(URLRequest(url: url))

        // Hide loading overlay
        loadingView.isHidden = true

        let version = serviceManager.readVersion()
        updateStatus("n8n v\(version) — port \(port)")

        // Start status polling
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkServiceHealth()
        }
    }

    func checkServiceHealth() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let ready = self.serviceManager.isReady()
            let port = self.serviceManager.readPort()
            let version = self.serviceManager.readVersion()
            DispatchQueue.main.async {
                if ready {
                    self.updateStatus("n8n v\(version) — port \(port)")
                } else {
                    self.updateStatus("n8n is not responding — port \(port)")
                }
            }
        }
    }

    func updateStatus(_ text: String) {
        statusItem?.stringValue = text
    }

    // MARK: - WKNavigationDelegate

    /// Restrict navigation to localhost only — block external URLs to prevent phishing.
    /// Only applies to the main webView (not the terminal webView).
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let host = url.host else {
            decisionHandler(.cancel)
            return
        }

        // Allow only localhost / 127.0.0.1 on the configured port
        let isLocalhost = (host == "127.0.0.1" || host == "localhost")
        let isAllowedPort = (url.port == nil || url.port == allowedPort)

        if isLocalhost && isAllowedPort {
            decisionHandler(.allow)
        } else {
            // Open external URLs in the default browser instead
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateStatus("Error: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // n8n might have restarted — show loading and retry
        loadingView.isHidden = false
        loadingLabel.stringValue = "Reconnecting..."
        spinner.startAnimation(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.ensureServiceRunning()
        }
    }

    // MARK: - Menu actions

    @objc func showAbout(_ sender: Any?) {
        let version = serviceManager.readVersion()
        let port = serviceManager.readPort()
        let alert = NSAlert()
        alert.messageText = "n8n"
        alert.informativeText = "Version: \(version)\nPort: \(port)\nInstall: ~/.n8n-local/"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func startService(_ sender: Any?) {
        updateStatus("Starting n8n...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serviceManager.start()
            Thread.sleep(forTimeInterval: 2.0)
            DispatchQueue.main.async {
                self?.ensureServiceRunning()
            }
        }
    }

    @objc func stopService(_ sender: Any?) {
        updateStatus("Stopping n8n...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serviceManager.stop()
            DispatchQueue.main.async {
                self?.updateStatus("n8n stopped")
            }
        }
    }

    @objc func restartService(_ sender: Any?) {
        loadingView.isHidden = false
        loadingLabel.stringValue = "Restarting n8n..."
        spinner.startAnimation(nil)
        updateStatus("Restarting n8n...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.serviceManager.stop()
            Thread.sleep(forTimeInterval: 1.5)
            DispatchQueue.main.async {
                self?.ensureServiceRunning()
            }
        }
    }

    @objc func showLogs(_ sender: Any?) {
        let logsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        logsWindow.title = "n8n Logs"
        logsWindow.center()

        let scrollView = NSScrollView(frame: logsWindow.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 8, height: 8)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let logs = self?.serviceManager.readLogs(lines: 200) ?? ""
            DispatchQueue.main.async {
                textView.string = logs
                textView.scrollToEndOfDocument(nil)
            }
        }

        scrollView.documentView = textView
        logsWindow.contentView = scrollView
        logsWindow.makeKeyAndOrderFront(nil)
    }

    @objc func reloadPage(_ sender: Any?) {
        webView.reload()
    }

    @objc func goBack(_ sender: Any?) {
        webView.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        webView.goForward()
    }

    // MARK: - Terminal panel

    @objc func toggleTerminal(_ sender: Any?) {
        guard let contentView = window.contentView else { return }

        if terminalVisible, let panel = terminalPanel {
            // Hide with slide-down animation
            // Reveal the toggle button as the panel slides away
            terminalToggleButton.isHidden = false
            terminalToggleButton.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
                var frame = panel.frame
                frame.origin.y -= 20
                panel.animator().frame = frame
                terminalToggleButton.animator().alphaValue = 1
            }, completionHandler: {
                panel.isHidden = true
                panel.alphaValue = 1
            })
            terminalVisible = false
            return
        }

        if let panel = terminalPanel {
            // Show existing panel (PTY preserved)
            panel.isHidden = false
            panel.alphaValue = 0
            let targetFrame = panel.frame
            let startFrame = NSRect(x: targetFrame.origin.x, y: targetFrame.origin.y - 20,
                                    width: targetFrame.width, height: targetFrame.height)
            panel.frame = startFrame
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
                panel.animator().frame = targetFrame
            })
            terminalToggleButton.isHidden = true
            terminalVisible = true
            panel.refitTerminal()
            return
        }

        // Check that terminal resources exist
        guard let resourcePath = Bundle.main.resourcePath,
              FileManager.default.fileExists(atPath: resourcePath + "/terminal-resources/terminal.html") else {
            let alert = NSAlert()
            alert.messageText = "Terminal Unavailable"
            alert.informativeText = "Terminal resources not found in the app bundle."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        // Create new panel
        let size = TerminalPanelView.defaultSize
        let margin = TerminalPanelView.margin
        let panelFrame = NSRect(
            x: contentView.bounds.width - size.width - margin,
            y: margin,
            width: size.width,
            height: size.height
        )

        let panel = TerminalPanelView(frame: panelFrame)
        panel.autoresizingMask = [] // Manually positioned
        contentView.addSubview(panel, positioned: .above, relativeTo: loadingView)

        // Slide-up animation
        panel.alphaValue = 0
        let startFrame = NSRect(x: panelFrame.origin.x, y: panelFrame.origin.y - 20,
                                width: panelFrame.width, height: panelFrame.height)
        panel.frame = startFrame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
            panel.animator().frame = panelFrame
        })

        panel.startTerminal()
        self.terminalPanel = panel
        self.terminalVisible = true
        terminalToggleButton.isHidden = true
    }

    @objc func handleTerminalClose(_ notification: Notification) {
        guard let panel = terminalPanel else { return }
        panel.killTerminal()
        panel.removeFromSuperview()
        terminalPanel = nil
        terminalVisible = false
        terminalToggleButton.isHidden = false
    }
}

/// A round, layer-backed button that shows the pointing-hand cursor on hover.
final class CircleIconButton: NSButton {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// Entry point is in main.swift
