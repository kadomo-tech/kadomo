import Foundation
import KadomoMenuCore

/// One theme the community catalog lists.
public struct OmarchyCommunityTheme: Sendable, Equatable, Codable {
    public var slug: String
    public var name: String
    public var author: String?
    public var description: String?
    public var repository: String
    /// Ships with Omarchy: installed from the official repository instead.
    public var builtin: Bool
    public var previewURL: String?
    /// The palette the catalog advertises, used for previews before installing.
    public var colors: [String: String]
    public var securityWarnings: [String]
}

public struct OmarchyOfficialListing: Sendable, Equatable, Codable {
    public var branch: String
    public var revision: String
    public var themes: [String]
    public var fetchedAt: Date
}

public struct OmarchyCommunityListing: Sendable, Equatable, Codable {
    public var themes: [OmarchyCommunityTheme]
    public var fetchedAt: Date
}

/// `catalog-cache.json`: the last listings that parsed, so the browsers work
/// offline and survive the catalogs changing or disappearing.
public struct OmarchyCatalogCache: Sendable, Equatable, Codable {
    public var official: OmarchyOfficialListing?
    public var community: OmarchyCommunityListing?
    public init(official: OmarchyOfficialListing? = nil, community: OmarchyCommunityListing? = nil) {
        self.official = official; self.community = community
    }

    /// A corrupt or unreadable cache is the same as none.
    public static func load(_ path: String) -> OmarchyCatalogCache {
        guard let data = FileManager.default.contents(atPath: path),
              let cache = try? OmarchyLibrary.decoder.decode(OmarchyCatalogCache.self, from: data) else { return OmarchyCatalogCache() }
        return cache
    }

    public func save(_ path: String) throws {
        try AtomicFile.write(try OmarchyLibrary.encoder.encode(self), to: path)
    }
}

/// Upstream endpoints. Everything about where Omarchy lives is here.
public struct OmarchyEndpoints: Sendable {
    public var officialOwner = "omacom"
    public var officialRepo = "omarchy"
    public var officialThemesPath = "themes"
    public var githubAPI = "https://api.github.com"
    public var raw = "https://raw.githubusercontent.com"
    public var communityCatalog = "https://omarchytheme.com/api/v1/themes.json"
    public init() {}
}

/// Parsing the upstream responses. Lenient about extra fields, strict about
/// the few it needs; a response it cannot read is a compatibility error, never
/// a crash, and never replaces a cache that worked.
public enum OmarchyCatalogFormat {
    public static func defaultBranch(_ data: Data) throws(OmarchyInstallError) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let branch = obj["default_branch"] as? String, OmarchyNames.isRefSafe(branch) else {
            throw OmarchyInstallError("GitHub's repository response changed (no default_branch)")
        }
        return branch
    }

    public static func commit(_ data: Data) throws(OmarchyInstallError) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = obj["sha"] as? String, sha.count == 40, sha.allSatisfy(\.isHexDigit) else {
            throw OmarchyInstallError("GitHub's commit response changed (no sha)")
        }
        return sha
    }

    public static func themeFolders(_ data: Data) throws(OmarchyInstallError) -> [String] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw OmarchyInstallError("the official themes folder listing changed (not a list)")
        }
        let names = list.compactMap { entry -> String? in
            guard entry["type"] as? String == "dir", let name = entry["name"] as? String, OmarchyNames.isValid(name) else { return nil }
            return name
        }
        guard !names.isEmpty else { throw OmarchyInstallError("the official repository lists no themes; its layout may have changed") }
        return names.sorted()
    }

    /// Still images in a GitHub folder listing; anything unexpected is left out.
    public static func backgroundFiles(_ data: Data) -> [String] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { entry -> String? in
            guard entry["type"] as? String == "file", let name = entry["name"] as? String,
                  SafeThemeCopy.imageKind(of: name) != nil, SafeThemeCopy.isPlainName(name), !name.hasPrefix("."),
                  (entry["size"] as? Int ?? 0) <= SafeThemeCopy.maxImageBytes else { return nil }
            return name
        }.sorted()
    }

    public static func community(_ data: Data) throws(OmarchyInstallError) -> [OmarchyCommunityTheme] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["themes"] as? [[String: Any]] else {
            throw OmarchyInstallError("the community catalog's format changed (no themes list)")
        }
        let themes = list.compactMap { e -> OmarchyCommunityTheme? in
            guard let slug = e["slug"] as? String, OmarchyNames.isValid(slug),
                  let name = e["name"] as? String, !name.isEmpty,
                  let repo = e["repository"] as? String, repo.lowercased().hasPrefix("https://") else { return nil }
            let colors = (e["colors"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
            return OmarchyCommunityTheme(
                slug: slug, name: String(name.prefix(80)), author: (e["author"] as? String).map { String($0.prefix(60)) },
                description: (e["description"] as? String).map { String($0.prefix(200)) }, repository: repo,
                builtin: e["builtin"] as? Bool ?? false, previewURL: e["preview_url"] as? String, colors: colors,
                securityWarnings: (e["security_warnings"] as? [String]) ?? [])
        }
        guard !themes.isEmpty || list.isEmpty else { throw OmarchyInstallError("the community catalog's entries changed format") }
        return themes
    }
}

extension OmarchyNames {
    /// A branch or tag name that is safe to put in a URL path.
    static func isRefSafe(_ ref: String) -> Bool {
        !ref.isEmpty && ref.count < 200 && !ref.contains("..") && !ref.hasPrefix("-")
            && ref.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._/-+".unicodeScalars.contains($0) }
    }
}

/// HTTP with short timeouts and a size cap. Off the main thread by being async.
struct OmarchyHTTP: Sendable {
    var maxBytes = 12 * 1024 * 1024
    /// One whole transfer. `timeoutInterval` below only limits the gaps between
    /// bytes, which a slow server can keep short for as long as it likes.
    var maxSeconds: TimeInterval = 300

    func get(_ urlString: String, accept: String = "*/*", session suppliedSession: URLSession? = nil) async throws(OmarchyInstallError) -> Data? {
        guard let url = URL(string: urlString), url.scheme == "https" else { throw OmarchyInstallError("bad URL \(urlString)") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("kadomo-menu", forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        // Cancel the transfer on every exit, including a size-limit failure.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = maxSeconds
        let session = suppliedSession ?? URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) } catch {
            throw OmarchyInstallError("\(url.host ?? "the server") is unreachable: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw OmarchyInstallError("\(url.host ?? "the server") answered \(status)\(status == 403 ? " (GitHub's rate limit? try again later)" : "")")
        }
        let tooLarge = OmarchyInstallError("\(url.lastPathComponent) is larger than \(maxBytes / 1_048_576) MB")
        if response.expectedContentLength > Int64(maxBytes) { throw tooLarge }
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < maxBytes else { throw tooLarge }
                data.append(byte)
            }
        } catch let error as OmarchyInstallError {
            throw error
        } catch {
            throw OmarchyInstallError("download failed: \(error.localizedDescription)")
        }
        return data
    }

    func require(_ urlString: String, accept: String = "*/*") async throws(OmarchyInstallError) -> Data {
        guard let data = try await get(urlString, accept: accept) else { throw OmarchyInstallError("not found: \(urlString)") }
        return data
    }
}
