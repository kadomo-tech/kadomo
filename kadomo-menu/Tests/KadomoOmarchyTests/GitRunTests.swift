import Foundation
import Testing
@testable import KadomoOmarchy

// OmarchyGit.run with /bin/sh in git's place: what matters is how it treats the
// process, whatever the process is.
private func sh(_ script: String, timeout: TimeInterval = 20, watching folder: String? = nil,
                maxBytes: Int64 = 1_000_000, maxOutput: Int = 1_000_000) throws(OmarchyInstallError) -> String {
    try OmarchyGit.run(["-c", script], executable: "/bin/sh", timeout: timeout, watching: folder, maxBytes: maxBytes, maxOutput: maxOutput)
}

@Test func gitOutputIsReturned() throws {
    #expect(try sh("echo abc") == "abc\n")
}

@Test func gitFailureReportsTheLastErrorLine() {
    #expect(throws: OmarchyInstallError("git: second")) { try sh("echo first >&2; echo second >&2; exit 3") }
}

@Test func gitFloodingStderrDoesNotStall() throws {
    let start = Date()
    #expect(try sh("head -c 2000000 /dev/zero | tr '\\0' x >&2; echo done", timeout: 15) == "done\n")
    #expect(Date().timeIntervalSince(start) < 10)
}

@Test func gitPrintingTooMuchIsStopped() {
    #expect(throws: OmarchyInstallError("git printed more than 1 MB")) {
        try sh("while :; do head -c 100000 /dev/zero | tr '\\0' x; done", maxOutput: 1_048_576)
    }
}

@Test func gitIgnoringTheSignalIsKilledAtTheDeadline() {
    let start = Date()
    #expect(throws: OmarchyInstallError("git timed out")) { try sh("trap '' TERM; while :; do sleep 1; done", timeout: 1) }
    #expect(Date().timeIntervalSince(start) < 8)
}

@Test func gitGrowingAFolderPastTheLimitIsStopped() throws {
    let folder = NSTemporaryDirectory() + "kadomo-git-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }
    do {
        _ = try sh("n=0; while :; do head -c 100000 /dev/zero >\"\(folder)/$n\"; n=$((n+1)); sleep 0.05; done", watching: folder)
        Issue.record("expected an error")
    } catch {
        #expect(error.message.contains("larger than a theme can be"))
    }
}

@Test func gitEnvironmentDropsGitVariables() {
    setenv("GIT_CONFIG_PARAMETERS", "'http.sslverify=false'", 1)
    defer { unsetenv("GIT_CONFIG_PARAMETERS") }
    #expect(OmarchyGit.environment["GIT_CONFIG_PARAMETERS"] == nil)
    #expect(OmarchyGit.environment["GIT_ALLOW_PROTOCOL"] == "https")
}
