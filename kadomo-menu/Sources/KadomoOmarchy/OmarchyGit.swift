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

    static let safety = [
        "-c", "core.hooksPath=/dev/null", "-c", "protocol.allow=never", "-c", "protocol.https.allow=always",
        "-c", "submodule.recurse=false", "-c", "core.symlinks=false", "-c", "core.fsmonitor=false",
        "-c", "credential.helper=", "-c", "http.followRedirects=initial",
    ]

    static var environment: [String: String] {
        // Git's own variables could point it at other config or programs. The
        // -c settings above are applied after GIT_CONFIG_PARAMETERS, so they win.
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") || $0.key == "GIT_CONFIG_PARAMETERS" }
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = "/usr/bin/false"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_LFS_SKIP_SMUDGE"] = "1"
        env["GIT_ALLOW_PROTOCOL"] = "https"
        return env
    }

    /// Shallow-clones `location` into `destination` and returns the commit.
    public static func clone(_ location: OmarchyGitLocation, into destination: String) throws(OmarchyInstallError) -> String {
        var args = safety + ["clone", "--quiet", "--depth", "1", "--no-recurse-submodules", "--no-tags", "--single-branch"]
        if let ref = location.ref { args += ["--branch", ref] }
        args += ["--", location.repository, destination]
        _ = try run(args)
        let sha = try run(safety + ["-C", destination, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sha
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

    @discardableResult
    static func run(_ args: [String]) throws(OmarchyInstallError) -> String {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw OmarchyInstallError("needs git (xcode-select --install)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw OmarchyInstallError("could not run git: \(error.localizedDescription)") }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errData, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? "exit \(process.terminationStatus)"
            throw OmarchyInstallError(process.terminationReason == .uncaughtSignal ? "git timed out" : "git: \(message.prefix(200))")
        }
        return String(decoding: outData, as: UTF8.self)
    }
}
