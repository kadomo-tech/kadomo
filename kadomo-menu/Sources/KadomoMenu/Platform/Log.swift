import Foundation
import os

/// Unified logging (Console.app, `log stream --predicate 'subsystem == "tech.kadomo.menu"'`),
/// mirrored to stderr when `debug_log = true`.
nonisolated enum Log {
    private static let logger = Logger(subsystem: "tech.kadomo.menu", category: "app")
    nonisolated(unsafe) static var debugEnabled = ProcessInfo.processInfo.environment["KADOMO_MENU_DEBUG"] == "1"

    static func debug(_ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        let m = message()
        logger.debug("\(m, privacy: .public)")
        mirror("debug", m)
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        mirror("info", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        mirror("error", message)
    }

    private static func mirror(_ level: String, _ message: String) {
        guard debugEnabled else { return }
        FileHandle.standardError.write(Data("[kadomo-menu] \(level): \(message)\n".utf8))
    }
}
