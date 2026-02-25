// TerminalManager.swift — PTY lifecycle: spawn shell, read/write, resize, cleanup
// Uses forkpty() to create a pseudo-terminal and runs /bin/zsh inside it.

import Foundation

class TerminalManager {

    var onOutput: ((Data) -> Void)?
    var onExit: (() -> Void)?

    private var masterFd: Int32 = -1
    private var childPid: pid_t = 0
    private var readSource: DispatchSourceRead?
    private let writeQueue = DispatchQueue(label: "com.n8n.terminal.write")
    private var exitTimer: DispatchSourceTimer?
    private var running = false

    var isRunning: Bool { running }

    /// Spawn a shell with the given terminal dimensions.
    func start(cols: Int = 80, rows: Int = 24) {
        guard !running else { return }

        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        ws.ws_xpixel = 0
        ws.ws_ypixel = 0

        var masterFd: Int32 = 0
        let pid = forkpty(&masterFd, nil, nil, &ws)

        if pid < 0 {
            // forkpty failed
            return
        }

        if pid == 0 {
            // Child process — exec the shell
            let installDir = NSHomeDirectory() + "/.n8n-local"
            let nodeBinPath = installDir + "/node/bin"
            let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
            let newPath = "\(nodeBinPath):\(existingPath)"

            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            setenv("PATH", newPath, 1)
            setenv("HOME", NSHomeDirectory(), 1)

            // Change to home directory
            chdir(NSHomeDirectory())

            // Build argv for execvp: ["zsh", "--login", NULL]
            let args = ["zsh", "--login"]
            let cArgs = args.map { strdup($0) } + [nil]
            execvp("/bin/zsh", cArgs)
            // If execvp fails, exit the child
            _exit(1)
        }

        // Parent process
        self.masterFd = masterFd
        self.childPid = pid
        self.running = true

        // Set non-blocking on master fd
        let flags = fcntl(masterFd, F_GETFL)
        _ = fcntl(masterFd, F_SETFL, flags | O_NONBLOCK)

        // Read PTY output via DispatchSource
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFd, queue: DispatchQueue.global(qos: .userInteractive))
        source.setEventHandler { [weak self] in
            guard let self = self, self.running else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(self.masterFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.onOutput?(data)
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN && errno != EINTR) {
                self.handleExit()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.masterFd >= 0 {
                close(self.masterFd)
                self.masterFd = -1
            }
        }
        source.resume()
        self.readSource = source

        // Poll for child exit via timer
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.running else { return }
            var status: Int32 = 0
            let result = waitpid(self.childPid, &status, WNOHANG)
            if result > 0 {
                self.handleExit()
            }
        }
        timer.resume()
        self.exitTimer = timer
    }

    /// Write data (user keystrokes) to the PTY.
    func write(_ data: Data) {
        guard running, masterFd >= 0 else { return }
        writeQueue.async { [weak self] in
            guard let self = self, self.masterFd >= 0 else { return }
            data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return }
                var written = 0
                let total = data.count
                while written < total {
                    let n = Foundation.write(self.masterFd, ptr + written, total - written)
                    if n < 0 {
                        if errno == EAGAIN || errno == EINTR { continue }
                        break
                    }
                    written += n
                }
            }
        }
    }

    /// Resize the PTY window.
    func resize(cols: Int, rows: Int) {
        guard running, masterFd >= 0 else { return }
        var ws = winsize()
        ws.ws_col = UInt16(cols)
        ws.ws_row = UInt16(rows)
        _ = ioctl(masterFd, UInt(TIOCSWINSZ), &ws)
    }

    /// Terminate the PTY and child process.
    func terminate() {
        guard running else { return }
        running = false

        exitTimer?.cancel()
        exitTimer = nil
        readSource?.cancel()
        readSource = nil

        if childPid > 0 {
            kill(childPid, SIGHUP)
            kill(childPid, SIGTERM)
            // Reap zombie
            var status: Int32 = 0
            waitpid(childPid, &status, 0)
            childPid = 0
        }

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
    }

    private func handleExit() {
        guard running else { return }
        running = false

        exitTimer?.cancel()
        exitTimer = nil
        readSource?.cancel()
        readSource = nil

        DispatchQueue.main.async { [weak self] in
            self?.onExit?()
        }
    }

    deinit {
        terminate()
    }
}
