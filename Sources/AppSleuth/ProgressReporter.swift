import Darwin
import Foundation

enum ProgressStyle {
    case quiet
    case normal
    case verbose
}

final class ProgressReporter {
    private let style: ProgressStyle
    private let interactive: Bool
    private let lock = NSLock()
    private var activeSpinner: TerminalSpinner?

    init(quiet: Bool, verbose: Bool) {
        self.style = quiet ? .quiet : (verbose ? .verbose : .normal)
        self.interactive = isatty(STDERR_FILENO) == 1
    }

    var isVerbose: Bool { style == .verbose }

    func activity<T>(_ message: String, operation: () throws -> T) rethrows -> T {
        guard style != .quiet else { return try operation() }
        if interactive && style == .normal {
            let spinner = TerminalSpinner(message: message)
            setActiveSpinner(spinner)
            spinner.start()
            defer {
                spinner.stop()
                setActiveSpinner(nil)
            }
            return try operation()
        }
        write("› \(message)\n")
        return try operation()
    }

    func detail(_ message: String) {
        if style == .verbose {
            write("  · \(message)\n")
        } else if style == .normal {
            currentSpinner()?.update(message: message)
        }
    }

    func success(_ message: String) {
        guard style != .quiet else { return }
        write("✓ \(message)\n")
    }

    private func write(_ value: String) {
        FileHandle.standardError.write(Data(value.utf8))
    }

    private func setActiveSpinner(_ spinner: TerminalSpinner?) {
        lock.lock()
        activeSpinner = spinner
        lock.unlock()
    }

    private func currentSpinner() -> TerminalSpinner? {
        lock.lock()
        defer { lock.unlock() }
        return activeSpinner
    }
}

private final class TerminalSpinner: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var message: String
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    init(message: String) {
        self.message = message
    }

    func start() {
        lock.lock()
        running = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var index = 0
            while true {
                let state = snapshot()
                guard state.running else { return }
                write("\r\u{001B}[2K\(frames[index % frames.count]) \(state.message)")
                index += 1
                usleep(80_000)
            }
        }
    }

    func update(message: String) {
        lock.lock()
        self.message = message
        lock.unlock()
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        usleep(90_000)
        write("\r\u{001B}[2K")
    }

    private func snapshot() -> (running: Bool, message: String) {
        lock.lock()
        defer { lock.unlock() }
        return (running, message)
    }

    private func write(_ value: String) {
        FileHandle.standardError.write(Data(value.utf8))
    }
}
