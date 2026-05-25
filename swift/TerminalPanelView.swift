// TerminalPanelView.swift — Floating terminal panel with embedded WKWebView + PTY bridge
// Anchored to bottom-right of the parent window, communicates with xterm.js via postMessage.

import Cocoa
import WebKit

class TerminalPanelView: NSView, WKScriptMessageHandler, WKNavigationDelegate {

    private var webView: WKWebView!
    private var titleBar: NSView!
    private var terminalManager: TerminalManager?
    private var isTerminalReady = false
    private var pendingOutput = Data()
    private var resizeHandle: NSView!
    private var initialDragPoint: NSPoint = .zero
    private var initialFrame: NSRect = .zero

    // Sizing
    static let defaultSize = NSSize(width: 500, height: 350)
    static let minSize = NSSize(width: 300, height: 200)
    static let margin: CGFloat = 16
    static let titleBarHeight: CGFloat = 28

    // Colors
    private let bgColor = NSColor(red: 0.118, green: 0.118, blue: 0.180, alpha: 1.0) // #1e1e2e
    private let titleBarColor = NSColor(red: 0.098, green: 0.098, blue: 0.149, alpha: 1.0) // slightly darker

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = bgColor.cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        // Shadow on the layer
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        layer?.shadowRadius = 12
        layer?.shadowOpacity = 0.5
        layer?.masksToBounds = false

        setupTitleBar()
        setupWebView()
        setupResizeHandle()
    }

    // MARK: - Title Bar

    private func setupTitleBar() {
        titleBar = NSView()
        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = titleBarColor.cgColor
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleBar)

        NSLayoutConstraint.activate([
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: TerminalPanelView.titleBarHeight)
        ])

        // Title label
        let label = NSTextField(labelWithString: "Terminal")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 1.0) // #cdd6f4
        label.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 12)
        ])

        // Close button
        let closeBtn = NSButton(frame: .zero)
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.title = "\u{2715}" // ✕
        closeBtn.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        closeBtn.contentTintColor = NSColor(red: 0.804, green: 0.839, blue: 0.957, alpha: 0.6)
        closeBtn.target = self
        closeBtn.action = #selector(closePanel)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(closeBtn)

        NSLayoutConstraint.activate([
            closeBtn.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -8),
            closeBtn.widthAnchor.constraint(equalToConstant: 24),
            closeBtn.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Drag gesture on title bar
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleTitleBarDrag(_:)))
        titleBar.addGestureRecognizer(panGesture)
    }

    // MARK: - WebView

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "terminal")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground") // transparent bg
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor, constant: TerminalPanelView.titleBarHeight),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Resize Handle

    private func setupResizeHandle() {
        resizeHandle = NSView()
        resizeHandle.wantsLayer = true
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 12),
            resizeHandle.heightAnchor.constraint(equalToConstant: 12)
        ])

        let resizeGesture = NSPanGestureRecognizer(target: self, action: #selector(handleResize(_:)))
        resizeHandle.addGestureRecognizer(resizeGesture)
    }

    // MARK: - Public API

    /// Load terminal HTML and start the PTY.
    func startTerminal() {
        guard let resourcePath = Bundle.main.resourcePath else {
            NSLog("TerminalPanelView: No resource path in bundle")
            return
        }

        let htmlPath = resourcePath + "/terminal-resources/terminal.html"
        let htmlURL = URL(fileURLWithPath: htmlPath)

        guard FileManager.default.fileExists(atPath: htmlPath) else {
            NSLog("TerminalPanelView: terminal.html not found at \(htmlPath)")
            return
        }

        let baseURL = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
    }

    /// Kill the PTY and reset state (used when user clicks X).
    func killTerminal() {
        terminalManager?.terminate()
        terminalManager = nil
        isTerminalReady = false
        pendingOutput = Data()
    }

    /// Trigger a re-fit of the terminal after panel resize.
    func refitTerminal() {
        guard isTerminalReady else { return }
        webView.evaluateJavaScript("window.terminalFit()") { [weak self] result, _ in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cols = dict["cols"] as? Int,
               let rows = dict["rows"] as? Int {
                self?.terminalManager?.resize(cols: cols, rows: rows)
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "ready":
            handleTerminalReady()
        case "input":
            if let text = body["data"] as? String, let data = text.data(using: .utf8) {
                if let manager = terminalManager, manager.isRunning {
                    manager.write(data)
                } else {
                    // Shell is dead — restart on Enter
                    handleInputWhileExited(data)
                }
            }
        case "resize":
            if let cols = body["cols"] as? Int, let rows = body["rows"] as? Int {
                terminalManager?.resize(cols: cols, rows: rows)
            }
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    /// Pin the terminal WebView to the bundled file:// page. Any attempt to navigate
    /// away (remote URLs, other local files) is blocked, so the shell-bridging message
    /// handler can never be driven by untrusted content.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Only allow file:// URLs inside the bundled terminal-resources directory.
        if url.isFileURL,
           let resourcePath = Bundle.main.resourcePath {
            let allowedDir = (resourcePath as NSString).appendingPathComponent("terminal-resources")
            let standardized = (url.path as NSString).standardizingPath
            if standardized == allowedDir || standardized.hasPrefix(allowedDir + "/") {
                decisionHandler(.allow)
                return
            }
        }

        decisionHandler(.cancel)
    }

    // MARK: - PTY Setup

    private func handleTerminalReady() {
        isTerminalReady = true

        // Flush any pending output
        if !pendingOutput.isEmpty {
            sendDataToJS(pendingOutput)
            pendingOutput = Data()
        }

        // Start PTY if not already running
        if terminalManager == nil {
            spawnPTY()
        }
    }

    private func spawnPTY() {
        let manager = TerminalManager()
        self.terminalManager = manager

        manager.onOutput = { [weak self] data in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isTerminalReady {
                    self.sendDataToJS(data)
                } else {
                    self.pendingOutput.append(data)
                }
            }
        }

        manager.onExit = { [weak self] in
            guard let self = self else { return }
            self.terminalManager = nil
            // Show exit message and allow restart
            let msg = "\r\n\u{001B}[1;33mShell exited. Press Enter to restart.\u{001B}[0m\r\n"
            if let data = msg.data(using: .utf8) {
                self.sendDataToJS(data)
            }
            self.awaitRestart()
        }

        // Get initial size from JS, then start
        if isTerminalReady {
            webView.evaluateJavaScript("window.terminalFit()") { [weak self] result, _ in
                var cols = 80
                var rows = 24
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    cols = dict["cols"] as? Int ?? 80
                    rows = dict["rows"] as? Int ?? 24
                }
                self?.terminalManager?.start(cols: cols, rows: rows)
            }
        } else {
            manager.start()
        }
    }

    /// After shell exits, intercept Enter key to restart.
    private func awaitRestart() {
        // Temporarily replace the message handler behavior:
        // The next "input" containing \r will trigger a new spawn
    }

    // Override input handling when shell is dead to detect Enter for restart
    private func handleInputWhileExited(_ data: Data) {
        if let str = String(data: data, encoding: .utf8), str.contains("\r") || str.contains("\n") {
            spawnPTY()
        }
    }

    private func sendDataToJS(_ data: Data) {
        let base64 = data.base64EncodedString()
        webView.evaluateJavaScript("window.terminalWrite('\(base64)')") { _, error in
            if let error = error {
                NSLog("TerminalPanelView: JS error: \(error)")
            }
        }
    }

    // MARK: - Gestures

    @objc private func handleTitleBarDrag(_ gesture: NSPanGestureRecognizer) {
        guard let superview = self.superview else { return }

        switch gesture.state {
        case .began:
            initialDragPoint = gesture.location(in: superview)
            initialFrame = self.frame
        case .changed:
            let current = gesture.location(in: superview)
            let dx = current.x - initialDragPoint.x
            let dy = current.y - initialDragPoint.y
            var newFrame = initialFrame
            newFrame.origin.x += dx
            newFrame.origin.y += dy
            // Clamp to parent bounds
            newFrame.origin.x = max(0, min(newFrame.origin.x, superview.bounds.width - newFrame.width))
            newFrame.origin.y = max(0, min(newFrame.origin.y, superview.bounds.height - newFrame.height))
            self.frame = newFrame
        default:
            break
        }
    }

    @objc private func handleResize(_ gesture: NSPanGestureRecognizer) {
        guard let superview = self.superview else { return }

        switch gesture.state {
        case .began:
            initialDragPoint = gesture.location(in: superview)
            initialFrame = self.frame
        case .changed:
            let current = gesture.location(in: superview)
            let dx = current.x - initialDragPoint.x
            let dy = current.y - initialDragPoint.y

            // Resize from top-left corner: move origin and adjust size
            var newWidth = initialFrame.width - dx
            var newHeight = initialFrame.height + dy

            newWidth = max(TerminalPanelView.minSize.width, newWidth)
            newHeight = max(TerminalPanelView.minSize.height, newHeight)

            var newX = initialFrame.origin.x + (initialFrame.width - newWidth)
            let newY = initialFrame.origin.y

            // Clamp
            if newX < 0 {
                newWidth += newX
                newX = 0
            }
            let maxHeight = superview.bounds.height - newY
            newHeight = min(newHeight, maxHeight)

            self.frame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            refitTerminal()
        case .ended:
            refitTerminal()
        default:
            break
        }
    }

    @objc private func closePanel() {
        // Notify the app delegate to handle hiding
        NotificationCenter.default.post(name: NSNotification.Name("TerminalPanelClose"), object: self)
    }

    // MARK: - Cursor Handling

    override func resetCursorRects() {
        addCursorRect(resizeHandle.frame, cursor: .crosshair)
    }
}
