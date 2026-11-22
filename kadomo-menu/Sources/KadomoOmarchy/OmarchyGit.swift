import Foundation

/// A public HTTPS Git location, optionally a folder inside it
/// (`https://github.com/owner/repo/tree/<ref>/<path>`).
public struct OmarchyGitLocation: Sendable, Equatable {
    public var repository: String
    public var ref: String?
    public var subpath: String?

    /// Accepts `https://host/owner/repo(.git)` and GitHub `tree/<ref>/<path>`
    /// links. Refuses anything that is not plain HTTPS: other transports,
    /// credentials in the URL, option-like or control characters.
    public static func parse(_ raw: String) throws(OmarchyInstallError) -> OmarchyGitLocation {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OmarchyInstallError("type or paste a Git URL") }
        guard text.lowercased().hasPrefix("https://") else {
            throw OmarchyInstallError("only https:// Git URLs are supported (got \(text.prefix(60)))")
        }
        guard !text.contains(where: { $0.isWhitespace || $0.isNewline || ($0.asciiValue.map { $0 < 0x20 || $0 == 0x7f } ?? false) }),
              let url = URL(string: text), let host = url.host, !host.isEmpty, !host.hasPrefix("-") else {
            throw OmarchyInstallError("not a valid URL: \(text.prefix(60))")
        }
        guard url.user == nil, url.password == nil else { throw OmarchyInstallError("URLs with a user name or password are refused") }
        guard url.query == nil, url.fragment == nil else { throw OmarchyInstallError("a Git URL has no ?query or #fragment") }

        var parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !parts.contains(".."), !parts.contains(where: { $0.hasPrefix("-") }) else {
            throw OmarchyInstallError("\(text.prefix(60)) does not name a repository")
        }
        if host.lowercased() == "github.com", parts.count >= 4, parts[2] == "tree" {
            let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
            let ref = parts[3]
            var sub = Array(parts.dropFirst(4))
            if let last = sub.last, last.hasSuffix(".git") { sub[sub.count - 1] = String(last.dropLast(4)) }
            return OmarchyGitLocation(repository: "https://github.com/\(parts[0])/\(repo)", ref: ref,
                                      subpath: sub.isEmpty ? nil : sub.joined(separator: "/"))
        }
        if let last = parts.last, last.hasSuffix(".git") { parts[parts.count - 1] = String(last.dropLast(4)) }
        return OmarchyGitLocation(repository: "https://\(host)/" + parts.joined(separator: "/"), ref: nil, subpath: nil)
    }

    /// The name Omarchy would give it: the repository (or folder), without
    /// `omarchy-` in front or `-theme` behind, as display text.
    public var themeName: String {
        let base = subpath.map { ($0 as NSString).lastPathComponent } ?? (repository as NSString).lastPathComponent
        var name = base.lowercased()
        if name.hasPrefix("omarchy-") { name.removeFirst(8) }
        if name.hasSuffix("-theme") { name.removeLast(6) }
        return OmarchyNames.display(name.isEmpty ? base : name)
    }
}

public enum OmarchyNames {
    /// "tokyo-night" → "Tokyo Night"; a word with a digit stays as is.
    public static func display(_ slug: String) -> String {
        slug.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " }).map { word in
            word.contains(where: \.isNumber) ? String(word) : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    /// Omarchy's own rule for theme folder names.
    public static func isValid(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, !name.isEmpty, name.count <= 100 else { return false }
        let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._+-")
        return first != "." && first != "-" && name.unicodeScalars.allSatisfy { ok.contains($0) }
    }
}

/// Runs `git` with everything that could execute theme-supplied code turned
/// off: no hooks, no submodules, no filters from your config, HTTPS only, no
/// credential prompts, and a time limit.
public enum OmarchyGit {
    public static let executable = "/usr/bin/git"
    public static let timeout: TimeInterval = 120
    /// A theme keeps at most 300 MB of wallpapers, so a clone past these is not
    /// one worth keeping, and a stranger's repository must not fill the disk.
    static let maxCloneBytes: Int64 = 1024 * 1024 * 1024
    static let maxCloneFiles = 100_000
    static let maxOutputBytes = 4 * 1024 * 1024

    static let safety = [
        "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never", "-c", "protocol.https.allow=always",
        "-c", "submodule.recurse=false", "-c", "core.symlinks=false", "-c", "core.fsmonitor=false",
        "-c", "credential.helper=", "-c", "http.followRedirects=initial",
    ]

    static var environment: [String: String] {
        // Git's own variables could point it at other config or programs.
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_LFS_SKIP_SMUDGE"] = "1"
        env["GIT_ALLOW_PROTOCOL"] = "https"
        return env
    }

    /// Fetches Git objects without checking out the remote work tree.
    public static func clone(_ location: OmarchyGitLocation, into destination: String) throws(OmarchyInstallError) -> String {
        var args = safety + ["-c", "fetch.unpackLimit=1", "clone", "--quiet", "--depth", "1",
                             "--no-checkout", "--no-recurse-submodules", "--no-tags", "--single-branch"]
        if let ref = location.ref { args += ["--branch", ref] }
        args += ["--", location.repository, destination]
        _ = try run(args, watching: destination)
        let sha = try run(safety + ["-C", destination, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sha
    }

    /// Reads raw Git blobs so repository attributes, symlinks and executable
    /// modes never affect the files staged for the theme importer.
    static func exportTheme(from repository: String, subpath: String?, into destination: String) throws(OmarchyInstallError) -> [String] {
        let git = safety + ["-C", repository]
        let tree = subpath.map { "HEAD:\($0)" } ?? "HEAD"
        let limits = SafeThemeCopy.limits.merging(["alacritty.toml": OmarchyAlacritty.maxBytes]) { first, _ in first }
        let files = try treeEntries(git: git, tree: tree)
        var notes: [String] = []
        for entry in files {
            let preview = SafeThemeCopy.previewNames.contains(entry.name)
            guard let limit = preview ? SafeThemeCopy.maxImageBytes : limits[entry.name] else { continue }
            guard let size = entry.size, size <= limit else {
                if entry.name == "colors.toml" { throw OmarchyInstallError("colors.toml must be a regular file under 64 KB") }
                notes.append("\(entry.name) is not a regular file or is over the size limit; skipped")
                continue
            }
            let content = try runBytes(git + ["cat-file", "blob", entry.object], maxOutput: size)
            try stage(content, at: destination + "/" + entry.name)
        }
        if files.contains(where: { $0.name == "backgrounds" && $0.mode == "040000" }) {
            let wallpapers = try treeEntries(git: git, tree: (subpath.map { "HEAD:\($0)/" } ?? "HEAD:") + "backgrounds")
            var count = 0, bytes = 0, inspectedBytes = 0, inspected = 0, lfs = 0, skipped = 0
            let inspectionBudget = SafeThemeCopy.maxBackgroundBytes + SafeThemeCopy.maxImageBytes
            for entry in wallpapers.sorted(by: { $0.name < $1.name }) {
                guard !entry.name.hasPrefix("."), SafeThemeCopy.isPlainName(entry.name),
                      SafeThemeCopy.imageKind(of: entry.name) != nil else { continue }
                guard count < SafeThemeCopy.maxBackgrounds, inspected < 2 * SafeThemeCopy.maxBackgrounds,
                      let size = entry.size, size <= SafeThemeCopy.maxImageBytes,
                      size <= SafeThemeCopy.maxBackgroundBytes - bytes, size <= inspectionBudget - inspectedBytes else {
                    skipped += 1
                    continue
                }
                inspected += 1
                inspectedBytes += size
                let content = try runBytes(git + ["cat-file", "blob", entry.object], maxOutput: size)
                if SafeThemeCopy.isImage(content) {
                    try stage(content, at: destination + "/backgrounds/" + entry.name)
                    count += 1
                    bytes += content.count
                } else if content.starts(with: "version https://git-lfs".utf8) {
                    lfs += 1
                } else {
                    skipped += 1
                }
            }
            if lfs > 0 { notes.append("backgrounds: skipped \(lfs) Git LFS image(s)") }
            if skipped > 0 { notes.append("backgrounds: skipped \(skipped) image(s) that did not validate or exceeded import limits") }
        }
        return notes
    }

    private struct TreeEntry {
        let name: String
        let mode: Substring
        let object: String
        let size: Int?
    }

    private static func treeEntries(git: [String], tree: String) throws(OmarchyInstallError) -> [TreeEntry] {
        try run(git + ["ls-tree", "-z", "-l", tree]).split(separator: "\0").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let fields = parts[0].split(separator: " ")
            guard fields.count == 4 else { return nil }
            let mode = fields[0]
            let size = (mode == "100644" || mode == "100755") ? Int(fields[3]).flatMap { $0 >= 0 ? $0 : nil } : nil
            return TreeEntry(name: String(parts[1]), mode: mode, object: String(fields[2]), size: size)
        }
    }

    private static func stage(_ data: Data, at path: String) throws(OmarchyInstallError) {
        let file = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .withoutOverwriting)
        } catch {
            throw OmarchyInstallError("could not stage \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// The commit the remote's branch (or HEAD) points at now.
    public static func remoteRevision(_ location: OmarchyGitLocation) throws(OmarchyInstallError) -> String {
        let out = try run(safety + ["ls-remote", "--", location.repository, location.ref.map { "refs/heads/\($0)" } ?? "HEAD"]
                          + (location.ref.map { ["refs/tags/\($0)"] } ?? []))
        guard let sha = out.split(separator: "\n").first?.split(separator: "\t").first, sha.count >= 40 else {
            throw OmarchyInstallError("\(location.repository) has no \(location.ref ?? "HEAD")")
        }
        return String(sha)
    }

    /// Runs git and stops it, with a signal and then for good, when it runs too
    /// long, prints too much, or grows `folder` past the limits. Both pipes are
    /// read as data arrives, so a server flooding one cannot stall the other.
    @discardableResult
    static func run(_ args: [String], executable: String = OmarchyGit.executable, timeout: TimeInterval = OmarchyGit.timeout,
                    watching folder: String? = nil, maxBytes: Int64 = OmarchyGit.maxCloneBytes, maxFiles: Int = OmarchyGit.maxCloneFiles,
                    maxOutput: Int = OmarchyGit.maxOutputBytes) throws(OmarchyInstallError) -> String {
        try String(decoding: runBytes(args, executable: executable, timeout: timeout, watching: folder,
                                      maxBytes: maxBytes, maxFiles: maxFiles, maxOutput: maxOutput), as: UTF8.self)
    }

    private static func runBytes(_ args: [String], executable: String = OmarchyGit.executable, timeout: TimeInterval = OmarchyGit.timeout,
                                 watching folder: String? = nil, maxBytes: Int64 = OmarchyGit.maxCloneBytes, maxFiles: Int = OmarchyGit.maxCloneFiles,
                                 maxOutput: Int = OmarchyGit.maxOutputBytes) throws(OmarchyInstallError) -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw OmarchyInstallError("needs git (xcode-select --install)")
        }
        let process = Process()
        if folder != nil {
            // macOS Bash uses 1024-byte blocks for its file-size limit.
            // Git and its children inherit the cap, including index-pack.
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-p", "-c", "ulimit -f \"$1\" || exit 1; shift; exec \"$@\"", "kadomo-git", String(maxBytes / 1024), executable] + args
        } else {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
        }
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let outText = PipeText(limit: maxOutput, keepsEnd: false), errText = PipeText(limit: 64 * 1024, keepsEnd: true)
        outText.read(out)
        errText.read(err)
        do { try process.run() } catch { throw OmarchyInstallError("could not run git: \(error.localizedDescription)") }

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var nextCheck: TimeInterval = 0
        var stopped: String?
        var killAt: TimeInterval?
        while process.isRunning {
            let now = ProcessInfo.processInfo.systemUptime
            if stopped == nil {
                if now >= deadline {
                    stopped = "git timed out"
                } else if outText.overflowed {
                    stopped = "git printed more than \(maxOutput / 1_048_576) MB"
                } else if let folder, now >= nextCheck {
                    nextCheck = now + 1
                    if isOver(folder, maxBytes: maxBytes, maxFiles: maxFiles) {
                        stopped = "the repository is larger than a theme can be (\(maxBytes / 1_048_576) MB or \(maxFiles) files)"
                    }
                }
                if stopped != nil {
                    process.terminate()
                    killAt = now + 2
                }
            } else if let at = killAt, now >= at {
                kill(process.processIdentifier, SIGKILL)
                killAt = nil
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        // The rest of the output; a child that outlived git may hold a pipe open, so not forever.
        let outputComplete = outText.waitForEnd(seconds: 2)
        _ = errText.waitForEnd(seconds: 2)
        if let stopped { throw OmarchyInstallError(stopped) }
        guard outputComplete else { throw OmarchyInstallError("git did not close its output") }
        if outText.overflowed { throw OmarchyInstallError("git printed more than \(maxOutput) bytes") }
        if let folder, isOver(folder, maxBytes: maxBytes, maxFiles: maxFiles) {
            throw OmarchyInstallError("the repository is larger than a theme can be")
        }
        guard process.terminationStatus == 0 else {
            let message = errText.string.split(separator: "\n").last.map(String.init) ?? "exit \(process.terminationStatus)"
            throw OmarchyInstallError("git: \(message.suffix(200))")
        }
        return outText.bytes
    }

    private static func isOver(_ folder: String, maxBytes: Int64, maxFiles: Int) -> Bool {
        guard let files = FileManager.default.enumerator(atPath: folder) else { return false }
        var bytes: Int64 = 0, count = 0
        while files.nextObject() != nil {
            count += 1
            bytes += (files.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
            if bytes > maxBytes || count > maxFiles { return true }
        }
        return false
    }
}

/// One of git's output pipes, read as data arrives and held up to a limit:
/// the start of it (and a flag past the limit), or only the end.
private final class PipeText: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var over = false
    private let limit: Int
    private let keepsEnd: Bool
    private let ended = DispatchSemaphore(value: 0)

    init(limit: Int, keepsEnd: Bool) {
        self.limit = limit
        self.keepsEnd = keepsEnd
    }

    func read(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                ended.signal()
            } else {
                append(chunk)
            }
        }
    }

    private func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        guard data.count > limit else { return }
        if keepsEnd { data.removeFirst(data.count - limit) } else { over = true; data.removeLast(data.count - limit) }
    }

    func waitForEnd(seconds: Double) -> Bool { ended.wait(timeout: .now() + seconds) == .success }

    var overflowed: Bool {
        lock.lock(); defer { lock.unlock() }
        return over
    }

    var bytes: Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    var string: String { String(decoding: bytes, as: UTF8.self) }
}
