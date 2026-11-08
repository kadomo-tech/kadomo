import Foundation
import KadomoMenuCore

/// The Omarchy integration's one entry point: discovery, installs, updates,
/// removal, and the cached appearances the launcher applies. Network and Git
/// work is async or blocking and must be called off the main thread; reading
/// an installed theme's appearance only reads its metadata file.
public struct OmarchyThemeService: Sendable {
    public let library: OmarchyLibrary
    public var endpoints: OmarchyEndpoints
    var http = OmarchyHTTP(maxBytes: 25 * 1024 * 1024)

    public init(library: OmarchyLibrary = OmarchyLibrary(), endpoints: OmarchyEndpoints = OmarchyEndpoints()) {
        self.library = library
        self.endpoints = endpoints
    }

    // MARK: Applying

    /// The last validated appearance of an installed theme. No parsing of
    /// theme files, no network.
    public func appearance(id: String) -> Result<ThemeAppearance, ExternalThemeError> {
        guard let record = library.record(id: id) else {
            return .failure(ExternalThemeError("it is not installed, or its metadata is unreadable"))
        }
        let problems = record.appearance.validate()
        guard problems.isEmpty else { return .failure(ExternalThemeError("its cached colors are unusable: \(problems.joined(separator: "; "))")) }
        return .success(record.appearance)
    }

    // MARK: Discovery

    public func loadCache() -> OmarchyCatalogCache { OmarchyCatalogCache.load(library.catalogCacheFile) }

    /// The official repository's themes at its current default branch.
    public func discoverOfficialThemes() async throws(OmarchyInstallError) -> OmarchyOfficialListing {
        let repo = "\(endpoints.githubAPI)/repos/\(endpoints.officialOwner)/\(endpoints.officialRepo)"
        let json = "application/vnd.github+json"
        let branch = try OmarchyCatalogFormat.defaultBranch(try await http.require(repo, accept: json))
        let sha = try OmarchyCatalogFormat.commit(try await http.require("\(repo)/commits/\(branch)", accept: json))
        let names = try OmarchyCatalogFormat.themeFolders(try await http.require("\(repo)/contents/\(endpoints.officialThemesPath)?ref=\(sha)", accept: json))
        let listing = OmarchyOfficialListing(branch: branch, revision: sha, themes: names, fetchedAt: Date())
        var cache = loadCache()
        cache.official = listing
        try? cache.save(library.catalogCacheFile)
        return listing
    }

    /// The third-party community catalog. Optional infrastructure: when it is
    /// down or changes shape, the last good listing stays cached.
    public func discoverCommunityThemes() async throws(OmarchyInstallError) -> OmarchyCommunityListing {
        let themes = OmarchyCatalogFormat.withBundled(try OmarchyCatalogFormat.community(try await http.require(endpoints.communityCatalog, accept: "application/json")))
        let listing = OmarchyCommunityListing(themes: themes, fetchedAt: Date())
        var cache = loadCache()
        cache.community = listing
        try? cache.save(library.catalogCacheFile)
        return listing
    }

    // MARK: Installing

    /// Downloads one official theme's files (no clone of the whole repository)
    /// at a pinned commit, then installs it through staging.
    @discardableResult
    /// `pinned` is an Omarchy release (a tag such as `v4.0.6`) to take the
    /// theme from: for official themes that later releases no longer ship. A
    /// pinned theme stays at that release. `fallback` is such a release to try
    /// when the current one has no theme of that name.
    public func installOfficial(_ name: String, revision: String? = nil, pinned: String? = nil,
                                fallback: String? = nil) async throws(OmarchyInstallError) -> OmarchyThemeRecord {
        guard OmarchyNames.isValid(name) else { throw OmarchyInstallError("'\(name)' is not an official theme name") }
        if pinned == nil, let fallback {
            do { return try await installOfficial(name, revision: revision) } catch {
                guard error.message.contains("has no theme") else { throw error }
                return try await installOfficial(name, pinned: fallback)
            }
        }
        if let pinned, !OmarchyNames.isRefSafe(pinned) { throw OmarchyInstallError("'\(pinned)' is not an Omarchy release") }
        let sha: String
        if let pinned { sha = pinned } else if let revision { sha = revision } else { sha = try await discoverOfficialThemes().revision }
        let download = library.stagingDirectory + "/download-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: download) }
        try? FileManager.default.createDirectory(atPath: download, withIntermediateDirectories: true)
        let base = "\(endpoints.raw)/\(endpoints.officialOwner)/\(endpoints.officialRepo)/\(sha)/\(endpoints.officialThemesPath)/\(name)/"
        guard let colors = try await http.get(base + "colors.toml") else {
            throw OmarchyInstallError("Omarchy \(pinned ?? "today") has no theme '\(name)' with a colors.toml")
        }
        try write(colors, download + "/colors.toml")
        for file in ["shell.toml", "light.mode", "preview.png", "btop.theme", "vscode.json"] {
            if let data = try? await http.get(base + file) { try write(data, download + "/" + file) }
        }
        // Its wallpapers: one listing call, then the files at the same commit.
        // A failure is recorded, not swallowed: the theme installs, is marked
        // incomplete, and the next update (or applying it) fetches it again.
        var complete = true, notes: [String] = []
        let listing = "\(endpoints.githubAPI)/repos/\(endpoints.officialOwner)/\(endpoints.officialRepo)/contents/\(endpoints.officialThemesPath)/\(name)/backgrounds?ref=\(sha)"
        do {
            if let data = try await http.get(listing, accept: "application/vnd.github+json") {
                let files = OmarchyCatalogFormat.backgroundFiles(data).prefix(SafeThemeCopy.maxBackgrounds)
                if !files.isEmpty { try? FileManager.default.createDirectory(atPath: download + "/backgrounds", withIntermediateDirectories: true) }
                var missed = 0
                for file in files {
                    let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file
                    if let image = try? await http.get(base + "backgrounds/" + encoded) { try write(image, download + "/backgrounds/" + file) } else { missed += 1 }
                }
                if missed > 0 { complete = false; notes.append("\(missed) wallpaper\(missed == 1 ? "" : "s") could not be downloaded; Update tries again") }
            }
        } catch {
            complete = false
            notes.append("wallpapers not fetched (\(error.message)); Update tries again")
        }
        return try library.install(from: download, source: OmarchySource(kind: .official, location: name, ref: pinned),
                                   name: OmarchyNames.display(name), revision: sha, author: pinned.map { "Omarchy \($0)" } ?? "Omarchy",
                                   complete: complete, notes: notes)
    }

    /// Clones a public HTTPS repository (or a folder in one) and installs it.
    @discardableResult
    public func installFromGit(_ url: String, name: String? = nil, author: String? = nil, summary: String? = nil) throws(OmarchyInstallError) -> OmarchyThemeRecord {
        let location = try OmarchyGitLocation.parse(url)
        if location.repository.lowercased() == "https://github.com/\(endpoints.officialOwner)/\(endpoints.officialRepo)",
           let sub = location.subpath, sub.hasPrefix(endpoints.officialThemesPath + "/") {
            throw OmarchyInstallError("that is an official theme; install it from Official Themes (kadomo-menu omarchy install \((sub as NSString).lastPathComponent))")
        }
        let clone = library.stagingDirectory + "/clone-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: clone) }
        try? FileManager.default.createDirectory(atPath: library.stagingDirectory, withIntermediateDirectories: true)
        let sha = try OmarchyGit.clone(location, into: clone)
        let folder = location.subpath.map { clone + "/" + $0 } ?? clone
        let source = OmarchySource(kind: .git, location: location.repository, ref: location.ref, subpath: location.subpath)
        return try library.install(from: folder, source: source, name: name ?? location.themeName, revision: sha, author: author, summary: summary)
    }

    /// Installs a community catalog entry: official ones from the official
    /// repository, the rest from their Git repository.
    @discardableResult
    public func installCommunity(_ theme: OmarchyCommunityTheme) async throws(OmarchyInstallError) -> OmarchyThemeRecord {
        if theme.builtin {
            return try await installOfficial(theme.slug, revision: loadCache().official?.revision, fallback: officialRelease(of: theme))
        }
        return try installFromGit(theme.repository, name: theme.name, author: theme.author, summary: theme.description)
    }

    /// The Omarchy release a catalog entry for an official theme points at
    /// (`.../omarchy/tree/v4.0.6/themes/<name>`), if it does.
    public func officialRelease(of theme: OmarchyCommunityTheme) -> String? {
        guard theme.builtin, let loc = try? OmarchyGitLocation.parse(theme.repository),
              loc.repository.lowercased() == "https://github.com/\(endpoints.officialOwner)/\(endpoints.officialRepo)",
              loc.subpath == "\(endpoints.officialThemesPath)/\(theme.slug)", let ref = loc.ref, OmarchyNames.isRefSafe(ref) else { return nil }
        return ref
    }

    /// Copies a folder on this Mac. The copy is independent of the original.
    @discardableResult
    public func importLocalTheme(_ path: String) throws(OmarchyInstallError) -> OmarchyThemeRecord {
        let folder = (Paths.expand(path) as NSString).standardizingPath
        let name = OmarchyNames.display((folder as NSString).lastPathComponent.replacingOccurrences(of: "omarchy-", with: "")
            .replacingOccurrences(of: "-theme", with: ""))
        return try library.install(from: folder, source: OmarchySource(kind: .local, location: folder), name: name)
    }

    /// Checks whether a folder would install, without installing it.
    public func checkCompatibility(_ path: String) -> Result<(ThemeAppearance, [String]), OmarchyInstallError> {
        let stage = library.stagingDirectory + "/check-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: stage) }
        do {
            try? FileManager.default.createDirectory(atPath: stage, withIntermediateDirectories: true)
            var warnings = try SafeThemeCopy.copy(from: (Paths.expand(path) as NSString).standardizingPath, to: stage)
            do {
                let (appearance, more) = try OmarchyAdapter.normalize(directory: stage, name: (path as NSString).lastPathComponent)
                warnings += more
                return .success((appearance, warnings))
            } catch { return .failure(OmarchyInstallError(error.message)) }
        } catch { return .failure(error) }
    }

    // MARK: Updating

    public enum UpdateResult: Sendable, Equatable {
        case upToDate
        case updated(OmarchyThemeRecord)
        /// Local imports are copies; there is nothing to fetch.
        case notApplicable
    }

    /// Fetches the source again and replaces the theme only if the new version
    /// validates. On failure the installed version stays in use and the error
    /// is recorded on it.
    public func updateTheme(id: String) async throws(OmarchyInstallError) -> UpdateResult {
        guard let record = library.record(id: id) else { throw OmarchyInstallError("no installed Omarchy theme '\(id)'") }
        do {
            switch record.source.kind {
            case .local:
                return .notApplicable
            case .official where record.source.ref != nil:
                // Pinned to an Omarchy release: only fetched again to complete it.
                guard (record.files ?? 1) < OmarchyLibrary.filesVersion else { return .upToDate }
                return .updated(try await installOfficial(record.source.location, pinned: record.source.ref))
            case .official:
                let listing = try await discoverOfficialThemes()
                guard listing.revision != record.sourceRevision || (record.files ?? 1) < OmarchyLibrary.filesVersion else { return .upToDate }
                let updated = try await installOfficial(record.source.location, revision: listing.revision)
                let same = updated.appearance == record.appearance && updated.warnings == record.warnings && (record.files ?? 1) == OmarchyLibrary.filesVersion
                return same ? .upToDate : .updated(updated)
            case .git:
                let location = OmarchyGitLocation(repository: record.source.location, ref: record.source.ref, subpath: record.source.subpath)
                let remote = try OmarchyGit.remoteRevision(location)
                guard remote != record.sourceRevision || (record.files ?? 1) < OmarchyLibrary.filesVersion else { return .upToDate }
                let url = location.repository + (location.ref.map { r in "/tree/\(r)" + (location.subpath.map { "/\($0)" } ?? "") } ?? "")
                return .updated(try installFromGit(url, name: record.name, author: record.author, summary: record.summary))
            }
        } catch {
            library.noteFailure(id: id, "update failed: \(error.message)")
            throw error
        }
    }

    public func removeTheme(id: String) throws(OmarchyInstallError) { try library.remove(id: id) }

    private func write(_ data: Data, _ path: String) throws(OmarchyInstallError) {
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { throw OmarchyInstallError("could not write \(path): \(error.localizedDescription)") }
    }
}
