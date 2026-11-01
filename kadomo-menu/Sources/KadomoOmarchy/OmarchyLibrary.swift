import Foundation
import KadomoMenuCore

/// Where an installed Omarchy theme came from.
public struct OmarchySource: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case official, git, local }
    public var kind: Kind
    /// The official theme name, the Git URL, or the local folder.
    public var location: String
    /// A branch or tag for Git sources.
    public var ref: String?
    /// The theme's folder inside a Git repository; nil for the root.
    public var subpath: String?

    public init(kind: Kind, location: String, ref: String? = nil, subpath: String? = nil) {
        self.kind = kind; self.location = location; self.ref = ref; self.subpath = subpath
    }

    /// The stable identity: provider-specific, so equal names from different
    /// sources never collide. `official:tokyo-night`, `git:github.com/a/b:root`, `local:my-theme`.
    public var themeID: String {
        switch kind {
        case .official: return "official:\(location)"
        case .local: return "local:\(((location as NSString).lastPathComponent).lowercased())"
        case .git:
            var s = location.lowercased()
            for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
            if s.hasSuffix("/") { s.removeLast() }
            if s.hasSuffix(".git") { s.removeLast(4) }
            return "git:\(s):\(subpath ?? "root")"
        }
    }

    public var summary: String {
        switch kind {
        case .official: "Official"
        case .local: "Local · " + (location as NSString).abbreviatingWithTildeInPath
        case .git: "Git · " + location.replacingOccurrences(of: "https://", with: "") + (subpath.map { " /\($0)" } ?? "")
        }
    }
}

public enum OmarchyCompatibility: String, Sendable, Codable {
    /// Validated by the current adapter.
    case compatible
    /// Its source no longer validates; the last good appearance is still used.
    case stale
}

/// `metadata/<slug>.json`: everything Kadomo knows about one installed theme,
/// including the last appearance that validated. Applying a theme reads only this.
public struct OmarchyThemeRecord: Sendable, Equatable, Codable {
    public var provider = "omarchy"
    public var id: String
    public var slug: String
    public var name: String
    public var author: String?
    public var summary: String?
    public var source: OmarchySource
    public var sourceRevision: String?
    public var adapterVersion: Int
    public var lastValidated: Date
    public var compatibilityStatus: OmarchyCompatibility
    /// The last failed update or revalidation, kept until one succeeds.
    public var lastError: String?
    public var installedAt: Date
    public var updatedAt: Date
    public var appearance: ThemeAppearance
    public var warnings: [String]
    /// The preview image's path in the theme folder, if any.
    public var preview: String?
    /// Which files Kadomo kept (`OmarchyLibrary.filesVersion`). Older installs
    /// are fetched again on update to pick up what is kept now.
    public var files: Int?
}

public struct OmarchyInstallError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Omarchy's own storage, physically apart from Kadomo's themes:
///
///     <root>/themes/<slug>/        the files Kadomo kept (an allowlist)
///     <root>/metadata/<slug>.json  OmarchyThemeRecord
///     <root>/catalog-cache.json    the last official and community listings
///     <root>/staging/              imports in progress; never read as themes
///
/// The default root is `~/Library/Application Support/kadomo-menu/integrations/omarchy`.
public struct OmarchyLibrary: Sendable {
    public let root: String

    public init(root: String = Paths.stateDirectory + "/integrations/omarchy") {
        self.root = root
    }

    /// 1: palette and preview only. 2: also wallpapers and btop.theme, so the
    /// whole desktop can follow the theme. 3: also vscode.json, the VS Code
    /// theme the theme names.
    public static let filesVersion = 3

    public var themesDirectory: String { root + "/themes" }
    public var metadataDirectory: String { root + "/metadata" }
    public var stagingDirectory: String { root + "/staging" }
    public var catalogCacheFile: String { root + "/catalog-cache.json" }

    public func themeDirectory(_ slug: String) -> String { themesDirectory + "/" + slug }
    func metadataFile(_ slug: String) -> String { metadataDirectory + "/" + slug + ".json" }

    /// A file-system-safe folder name for an id: readable, plus a hash so ids
    /// that sanitize alike still get their own folders.
    public static func slug(for id: String) -> String {
        let tail = id.split(separator: ":").dropFirst().joined(separator: "-")
        var name = String(tail.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        name = String(name.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(60))
        var hash: UInt32 = 2166136261
        for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return (name.isEmpty ? "theme" : name) + "-" + String(format: "%08x", hash)
    }

    // MARK: Reading

    /// Every readable record, by name. Unreadable metadata is reported, not fatal.
    public func records() -> (records: [OmarchyThemeRecord], problems: [String]) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: metadataDirectory)) ?? []
        var out: [OmarchyThemeRecord] = []
        var problems: [String] = []
        for file in names.sorted() where file.hasSuffix(".json") && !file.hasPrefix(".") {
            let path = metadataDirectory + "/" + file
            guard let data = fm.contents(atPath: path) else { continue }
            do {
                out.append(try Self.decoder.decode(OmarchyThemeRecord.self, from: data))
            } catch {
                problems.append("\(file): unreadable metadata (\(error.localizedDescription))")
            }
        }
        return (out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, problems)
    }

    public func record(id: String) -> OmarchyThemeRecord? {
        guard let data = FileManager.default.contents(atPath: metadataFile(Self.slug(for: id))) else { return nil }
        return try? Self.decoder.decode(OmarchyThemeRecord.self, from: data)
    }

    // MARK: Installing

    /// Copies an Omarchy theme folder in through staging, validates it, and
    /// only then swaps it into place. A failure leaves an installed theme of
    /// the same id, its files, and its appearance exactly as they were.
    @discardableResult
    /// `complete` false (some files could not be fetched) records an older
    /// files version, so the next update fetches it again. `notes` join the warnings.
    public func install(from directory: String, source: OmarchySource, name: String, revision: String? = nil,
                        author: String? = nil, summary: String? = nil, complete: Bool = true, notes: [String] = [],
                        now: Date = Date()) throws(OmarchyInstallError) -> OmarchyThemeRecord {
        let fm = FileManager.default
        // Whole seconds: what the ISO 8601 metadata keeps.
        let now = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let id = source.themeID
        let slug = Self.slug(for: id)
        let stage = stagingDirectory + "/" + UUID().uuidString
        defer { try? fm.removeItem(atPath: stage) }
        do {
            try fm.createDirectory(atPath: stage, withIntermediateDirectories: true)
        } catch {
            throw OmarchyInstallError("could not create \(stage): \(error.localizedDescription)")
        }

        var warnings = notes + (try SafeThemeCopy.copy(from: directory, to: stage))
        let appearance: ThemeAppearance
        do {
            let (a, w) = try OmarchyAdapter.normalize(directory: stage, name: name)
            appearance = a
            warnings += w
        } catch {
            throw OmarchyInstallError("\(name) is not a theme Kadomo can use: \(error.message)")
        }

        let previous = record(id: id)
        let target = themeDirectory(slug)
        let old = stagingDirectory + "/old-" + UUID().uuidString
        do {
            try fm.createDirectory(atPath: themesDirectory, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: metadataDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: target) { try fm.moveItem(atPath: target, toPath: old) }
            try fm.moveItem(atPath: stage, toPath: target)
        } catch {
            if fm.fileExists(atPath: old), !fm.fileExists(atPath: target) { try? fm.moveItem(atPath: old, toPath: target) }
            throw OmarchyInstallError("could not move \(name) into place: \(error.localizedDescription)")
        }
        try? fm.removeItem(atPath: old)

        let preview = ((try? fm.contentsOfDirectory(atPath: target)) ?? []).first { $0.hasPrefix("preview.") }
            ?? ((try? fm.contentsOfDirectory(atPath: target + "/backgrounds")) ?? []).sorted().first.map { "backgrounds/" + $0 }
        let record = OmarchyThemeRecord(
            id: id, slug: slug, name: name, author: author ?? previous?.author, summary: summary ?? previous?.summary,
            source: source, sourceRevision: revision, adapterVersion: OmarchyAdapter.version, lastValidated: now,
            compatibilityStatus: .compatible, lastError: nil, installedAt: previous?.installedAt ?? now, updatedAt: now,
            appearance: appearance, warnings: warnings, preview: preview, files: complete ? Self.filesVersion : 1)
        do { try save(record) } catch {
            throw OmarchyInstallError("could not save \(name)'s metadata: \(error.localizedDescription)")
        }
        return record
    }

    public func save(_ record: OmarchyThemeRecord) throws {
        try AtomicFile.write(try Self.encoder.encode(record), to: metadataFile(record.slug))
    }

    /// Records a failed update or check without touching the installed files
    /// or the appearance in use.
    public func noteFailure(id: String, _ message: String) {
        guard var record = record(id: id) else { return }
        record.lastError = message
        try? save(record)
    }

    /// Deletes one theme's files and metadata. Only paths inside this library.
    public func remove(id: String) throws(OmarchyInstallError) {
        let slug = Self.slug(for: id)
        let fm = FileManager.default
        guard record(id: id) != nil || fm.fileExists(atPath: themeDirectory(slug)) else {
            throw OmarchyInstallError("no installed Omarchy theme '\(id)'")
        }
        for path in [themeDirectory(slug), metadataFile(slug)] where path.hasPrefix(root + "/") {
            do { if fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) } } catch {
                throw OmarchyInstallError("could not remove \(path): \(error.localizedDescription)")
            }
        }
    }

    /// Re-runs the adapter on installed files written by an older adapter.
    /// A theme that no longer validates keeps its last good appearance and is
    /// marked stale. Returns the records that changed.
    @discardableResult
    public func revalidateOutdated(now: Date = Date()) -> [OmarchyThemeRecord] {
        var changed: [OmarchyThemeRecord] = []
        for var record in records().records where record.adapterVersion < OmarchyAdapter.version {
            do {
                let (appearance, warnings) = try OmarchyAdapter.normalize(directory: themeDirectory(record.slug), name: record.name)
                record.appearance = appearance
                record.warnings = warnings
                record.compatibilityStatus = .compatible
                record.lastError = nil
                record.lastValidated = now
            } catch {
                record.compatibilityStatus = .stale
                record.lastError = "adapter \(OmarchyAdapter.version) cannot read it: \(error.message)"
            }
            record.adapterVersion = OmarchyAdapter.version
            try? save(record)
            changed.append(record)
        }
        return changed
    }

    /// Leftovers from an interrupted import.
    public func clearStaging() {
        try? FileManager.default.removeItem(atPath: stagingDirectory)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Copies only the files Kadomo uses from an untrusted theme folder. Nothing
/// is executed or followed: symlinks are refused, names are checked, sizes and
/// image types are limited. Everything else in the folder is ignored.
public enum SafeThemeCopy {
    /// Color data only. `btop.theme` is the one app config kept: it is a list
    /// of colors, and the theme manager checks it again when it is applied.
    /// `vscode.json` names the VS Code theme to install from the Marketplace;
    /// the theme manager checks its name and id before VS Code installs it.
    static let limits: [String: Int] = ["colors.toml": OmarchyPalette.maxBytes, "shell.toml": OmarchyShellStyle.maxBytes,
                                        "light.mode": 4096, "btop.theme": 64 * 1024, "vscode.json": 4096]
    static let previewNames = ["preview.png", "preview.jpg", "preview.jpeg", "preview.webp"]
    static let maxImageBytes = 25 * 1024 * 1024
    /// Wallpapers: at most this many, and this much in all.
    static let maxBackgrounds = 40
    static let maxBackgroundBytes = 300 * 1024 * 1024

    public static func copy(from source: String, to destination: String) throws(OmarchyInstallError) -> [String] {
        let fm = FileManager.default
        var warnings: [String] = []
        guard let kind = fileType(source), kind == .typeDirectory else {
            throw OmarchyInstallError("\(source) is not a folder (symlinked folders are refused)")
        }
        for (name, limit) in limits {
            let path = source + "/" + name
            guard let type = fileType(path) else { continue }
            guard type == .typeRegular else {
                if name == "colors.toml" { throw OmarchyInstallError("colors.toml is a symlink or not a file; refused") }
                warnings.append("\(name) is a symlink or not a file; skipped")
                continue
            }
            guard let size = fileSize(path), size <= limit else {
                if name == "colors.toml" { throw OmarchyInstallError("colors.toml is larger than \(limit / 1024) KB") }
                warnings.append("\(name) is too large; skipped")
                continue
            }
            do { try fm.copyItem(atPath: path, toPath: destination + "/" + name) } catch {
                throw OmarchyInstallError("could not copy \(name): \(error.localizedDescription)")
            }
        }
        // An older theme: its palette from alacritty.toml (that file is not kept).
        let alacritty = source + "/alacritty.toml"
        if !fm.fileExists(atPath: destination + "/colors.toml"), fileType(alacritty) == .typeRegular {
            guard let size = fileSize(alacritty), size <= OmarchyAlacritty.maxBytes,
                  let data = fm.contents(atPath: alacritty), let text = String(data: data, encoding: .utf8) else {
                throw OmarchyInstallError("alacritty.toml is unreadable or larger than 64 KB")
            }
            do {
                try Data(try OmarchyAlacritty.colorsTOML(text).utf8).write(to: URL(fileURLWithPath: destination + "/colors.toml"))
            } catch let error as OmarchyFormatError {
                throw OmarchyInstallError(error.message)
            } catch {
                throw OmarchyInstallError("could not write colors.toml: \(error.localizedDescription)")
            }
            warnings.append("an older theme: its colors come from alacritty.toml")
        }
        guard fm.fileExists(atPath: destination + "/colors.toml") else {
            throw OmarchyInstallError("no colors.toml or alacritty.toml: not an Omarchy theme")
        }

        // The preview image, then the wallpapers: still images only, checked by
        // their content, under plain names, copied (never linked).
        for name in previewNames {
            let path = source + "/" + name
            guard let type = fileType(path) else { continue }
            if type == .typeRegular, let data = readImage(path) {
                try? data.write(to: URL(fileURLWithPath: destination + "/" + name))
                break
            }
            warnings.append("\(name) is a symlink or not a PNG, JPEG, or WebP under 25 MB; skipped")
        }
        if fileType(source + "/backgrounds") == .typeDirectory {
            let names = ((try? fm.contentsOfDirectory(atPath: source + "/backgrounds")) ?? []).sorted()
            var kept = 0, total = 0, lfs = 0, skipped: [String] = []
            for name in names where !name.hasPrefix(".") {
                let path = source + "/backgrounds/" + name
                guard fileType(path) == .typeRegular else {
                    if fileType(path) == .typeSymbolicLink { skipped.append(name) }
                    continue // folders such as intros/ (videos) are not wallpapers
                }
                guard imageKind(of: name) != nil, isPlainName(name), kept < maxBackgrounds,
                      let data = readImage(path), total + data.count <= maxBackgroundBytes else {
                    if isLFSPointer(path) { lfs += 1 } else { skipped.append(name) }
                    continue
                }
                if kept == 0 { try? fm.createDirectory(atPath: destination + "/backgrounds", withIntermediateDirectories: false) }
                do { try data.write(to: URL(fileURLWithPath: destination + "/backgrounds/" + name)) } catch { skipped.append(name); continue }
                kept += 1
                total += data.count
            }
            if lfs > 0 { warnings.append("backgrounds: \(lfs) image\(lfs == 1 ? " is" : "s are") stored with Git LFS, which Kadomo does not download; a wallpaper is drawn from the colors instead") }
            if !skipped.isEmpty { warnings.append("backgrounds: skipped \(skipped.prefix(5).joined(separator: ", "))\(skipped.count > 5 ? " and \(skipped.count - 5) more" : "") (not a still image, a symlink, or over the limits)") }
        }
        return warnings
    }

    /// The file's bytes when it is a PNG, JPEG, or WebP under the size limit.
    static func readImage(_ path: String) -> Data? {
        guard let size = fileSize(path), size <= maxImageBytes, let data = FileManager.default.contents(atPath: path), isImage(data) else { return nil }
        return data
    }

    /// A Git LFS placeholder in place of the real file.
    static func isLFSPointer(_ path: String) -> Bool {
        guard let size = fileSize(path), size < 1024, let data = FileManager.default.contents(atPath: path) else { return false }
        return String(decoding: data.prefix(40), as: UTF8.self).hasPrefix("version https://git-lfs")
    }

    /// A wallpaper file name the theme manager can show and list: no control
    /// characters, no path separators.
    static func isPlainName(_ name: String) -> Bool {
        name.count <= 120 && !name.contains("/") && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }

    static func fileType(_ path: String) -> FileAttributeType? {
        // attributesOfItem does not follow a final symlink, so a link reports as a link.
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
    }

    static func fileSize(_ path: String) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue
    }

    static func imageKind(of name: String) -> String? {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp"].contains(ext) ? ext : nil
    }

    /// PNG, JPEG, or WebP by their first bytes, whatever the file is called.
    public static func isImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if b.count >= 12, b.starts(with: Array("RIFF".utf8)), Array(b[8..<12]) == Array("WEBP".utf8) { return true }
        return false
    }
}
