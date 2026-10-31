import AppKit
import KadomoMenuCore

/// Runs actions without blocking the UI. Executables get an argument array
/// and never pass through a shell; `shell` actions exist only when a user
/// wrote one in their own configuration.
enum Executor {
    /// GUI apps start with a minimal PATH. Add the usual tool locations so
    /// user commands can name `git` or `yabai` without a full path.
    nonisolated static let searchPath: String = {
        let base = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/.cargo/bin"]
        var parts = base.split(separator: ":").map(String.init)
        for e in extra where !parts.contains(e) { parts.append(e) }
        return parts.joined(separator: ":")
    }()

    nonisolated static func which(_ name: String) -> String? {
        if name.contains("/") {
            let p = Paths.expand(name)
            return FileManager.default.isExecutableFile(atPath: p) ? p : nil
        }
        for dir in searchPath.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Runs `action`. `done` gets nil on success or a message saying what went wrong.
    static func run(_ action: Action, title: String, done: @escaping @MainActor (String?) -> Void) {
        switch action {
        case .none, .navigate, .builtin:
            done(nil)

        case .openApp(let target, let newInstance):
            guard let url = resolveApp(target) else {
                done("\(title) could not be found. It may have been moved or uninstalled.")
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = newInstance
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                let message = error.map { "\(title) did not open: \($0.localizedDescription)" }
                Task { @MainActor in done(message) }
            }

        case .exec(let path, let args):
            guard let exe = which(path) else {
                done("\(title): '\(path)' was not found or is not executable.")
                return
            }
            spawn(exe, args.map(Paths.expand), title: title, done: done)

        case .shell(let script, let shell):
            guard let exe = which(shell) else { done("\(title): shell '\(shell)' was not found."); return }
            spawn(exe, ["-c", script], title: title, done: done)

        case .openURL(let s):
            guard let url = URL(string: s), NSWorkspace.shared.open(url) else {
                done("\(title): nothing can open \(s).")
                return
            }
            done(nil)

        case .openPath(let p):
            let path = Paths.expand(p)
            guard FileManager.default.fileExists(atPath: path) else { done("\(title): \(path) does not exist."); return }
            done(NSWorkspace.shared.open(URL(fileURLWithPath: path)) ? nil : "\(title): could not open \(path).")

        case .revealInFinder(let p):
            let path = Paths.expand(p)
            guard FileManager.default.fileExists(atPath: path) else { done("\(path) does not exist."); return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            done(nil)

        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            done(nil)
        }
    }

    /// A bundle path, a bundle identifier, or an app name.
    static func resolveApp(_ target: String) -> URL? {
        let expanded = Paths.expand(target)
        if expanded.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) { return url }
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
            let p = "\(dir)/\(target).app"
            if FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    /// Starts a process and reports a non-zero exit with the tail of stderr.
    /// Long-running commands are fine: nothing waits on them.
    static func spawn(_ exe: String, _ args: [String], title: String, done: @escaping @MainActor (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let tail = ErrorTail()
        errors.fileHandleForReading.readabilityHandler = { handle in tail.append(handle.availableData) }
        // The handler holds the process until it exits; Foundation drops the handler afterwards.
        process.terminationHandler = { p in
            withExtendedLifetime(process) {}
            errors.fileHandleForReading.readabilityHandler = nil
            let status = p.terminationStatus
            let reason = p.terminationReason
            let message: String? = status == 0 ? nil : {
                let detail = tail.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let what = reason == .uncaughtSignal ? "was killed by signal \(status)" : "exited with status \(status)"
                return "\(title) \(what)" + (detail.isEmpty ? "." : ": \(detail.split(separator: "\n").last ?? "")")
            }()
            Task { @MainActor in done(message) }
        }
        do {
            try process.run()
        } catch {
            done("\(title) could not start: \(error.localizedDescription)")
        }
    }

    /// The last 4 KB of a process's stderr.
    nonisolated final class ErrorTail: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ d: Data) {
            lock.lock(); defer { lock.unlock() }
            data.append(d)
            if data.count > 4096 { data.removeFirst(data.count - 4096) }
        }
        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}
