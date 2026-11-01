import Foundation

/// A small TOML parser covering what config, theme, and command files need:
/// tables, arrays of tables, dotted keys, basic/literal/multiline strings,
/// integers, floats, booleans, arrays, and inline tables. Dates are rejected
/// with a clear error. Every key remembers its line for diagnostics.
public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int? { if case .int(let i) = self { i } else { nil } }
    public var double: Double? {
        switch self {
        case .double(let d): d
        case .int(let i): Double(i)
        default: nil
        }
    }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [TOMLValue]? { if case .array(let a) = self { a } else { nil } }
    public var table: TOMLTable? { if case .table(let t) = self { t } else { nil } }

    public var typeName: String {
        switch self {
        case .string: "string"
        case .int: "integer"
        case .double: "float"
        case .bool: "boolean"
        case .array: "array"
        case .table: "table"
        }
    }
}

public struct TOMLTable: Sendable, Equatable {
    public private(set) var keys: [String] = []
    private var values: [String: TOMLValue] = [:]
    private var lines: [String: Int] = [:]

    public init() {}

    public subscript(key: String) -> TOMLValue? { values[key] }
    public func line(of key: String) -> Int? { lines[key] }

    public mutating func set(_ key: String, _ value: TOMLValue, line: Int? = nil) {
        if values[key] == nil { keys.append(key) }
        values[key] = value
        if let line, lines[key] == nil { lines[key] = line }
    }
}

public struct TOMLError: Error, Equatable, CustomStringConvertible {
    public var line: Int
    public var message: String
    public var description: String { "line \(line): \(message)" }
}

public enum TOML {
    public static func parse(_ text: String) throws(TOMLError) -> TOMLTable {
        var parser = Parser(bytes: Array(text.utf8))
        return try parser.document()
    }
}

private struct Parser {
    let bytes: [UInt8]
    var i = 0
    var line = 1

    init(bytes: [UInt8]) {
        // Skip a UTF-8 byte order mark.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { self.bytes = Array(bytes.dropFirst(3)) } else { self.bytes = bytes }
    }

    var atEnd: Bool { i >= bytes.count }
    var c: UInt8 { i < bytes.count ? bytes[i] : 0 }
    func peek(_ n: Int) -> UInt8 { i + n < bytes.count ? bytes[i + n] : 0 }

    func fail(_ message: String) -> TOMLError { TOMLError(line: line, message: message) }

    mutating func document() throws(TOMLError) -> TOMLTable {
        var root = TOMLTable()
        var current: [String] = []
        while true {
            skipBlank(newlines: true)
            if atEnd { break }
            if c == UInt8(ascii: "[") {
                let headerLine = line
                if peek(1) == UInt8(ascii: "[") {
                    i += 2
                    let path = try keyPath()
                    try expect("]"); try expect("]")
                    try withTable(Array(path.dropLast()), in: &root) { (t: inout TOMLTable) throws(TOMLError) in
                        let last = path.last!
                        switch t[last] {
                        case nil:
                            t.set(last, .array([.table(TOMLTable())]), line: headerLine)
                        case .array(var items)? where items.allSatisfy({ $0.table != nil }):
                            items.append(.table(TOMLTable()))
                            t.set(last, .array(items))
                        default:
                            throw TOMLError(line: headerLine, message: "'\(path.joined(separator: "."))' is already defined and is not an array of tables")
                        }
                    }
                    current = path
                } else {
                    i += 1
                    let path = try keyPath()
                    try expect("]")
                    try withTable(path, in: &root) { (_: inout TOMLTable) throws(TOMLError) in }
                    current = path
                }
                try endOfLine()
                continue
            }
            let keyLine = line
            let path = try keyPath()
            skipBlank(newlines: false)
            try expect("=")
            skipBlank(newlines: false)
            let value = try value()
            try withTable(current + path.dropLast(), in: &root) { (t: inout TOMLTable) throws(TOMLError) in
                let last = path.last!
                if t[last] != nil { throw TOMLError(line: keyLine, message: "duplicate key '\(last)'") }
                t.set(last, value, line: keyLine)
            }
            try endOfLine()
        }
        return root
    }

    /// Runs `body` on the table at `path`, creating tables on the way and
    /// descending into the last element of arrays of tables.
    func withTable(_ path: [String], in table: inout TOMLTable, _ body: (inout TOMLTable) throws(TOMLError) -> Void) throws(TOMLError) {
        guard let key = path.first else { try body(&table); return }
        let rest = Array(path.dropFirst())
        switch table[key] {
        case nil:
            var child = TOMLTable()
            try withTable(rest, in: &child, body)
            table.set(key, .table(child), line: line)
        case .table(var child)?:
            try withTable(rest, in: &child, body)
            table.set(key, .table(child))
        case .array(var items)? where items.last?.table != nil:
            var child = items[items.count - 1].table!
            try withTable(rest, in: &child, body)
            items[items.count - 1] = .table(child)
            table.set(key, .array(items))
        default:
            throw fail("'\(key)' is a value, not a table")
        }
    }

    mutating func skipBlank(newlines: Bool) {
        while !atEnd {
            switch c {
            case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r"): i += 1
            case UInt8(ascii: "\n"):
                guard newlines else { return }
                i += 1; line += 1
            case UInt8(ascii: "#"):
                while !atEnd && c != UInt8(ascii: "\n") { i += 1 }
            default: return
            }
        }
    }

    mutating func endOfLine() throws(TOMLError) {
        skipBlank(newlines: false)
        if atEnd { return }
        guard c == UInt8(ascii: "\n") else { throw fail("expected a new line, found '\(Character(UnicodeScalar(c)))'") }
        i += 1; line += 1
    }

    mutating func expect(_ ch: Character) throws(TOMLError) {
        skipBlank(newlines: false)
        guard !atEnd, c == ch.asciiValue! else {
            throw fail(atEnd ? "expected '\(ch)', found end of file" : "expected '\(ch)', found '\(Character(UnicodeScalar(c)))'")
        }
        i += 1
    }

    mutating func keyPath() throws(TOMLError) -> [String] {
        var parts: [String] = []
        repeat {
            skipBlank(newlines: false)
            parts.append(try key())
            skipBlank(newlines: false)
            if c == UInt8(ascii: ".") { i += 1 } else { break }
        } while true
        return parts
    }

    mutating func key() throws(TOMLError) -> String {
        if c == UInt8(ascii: "\"") { return try basicString() }
        if c == UInt8(ascii: "'") { return try literalString() }
        let start = i
        while !atEnd, isBareKey(c) { i += 1 }
        guard i > start else { throw fail(atEnd ? "expected a key" : "invalid character '\(Character(UnicodeScalar(c)))' in key") }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    func isBareKey(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x2D
    }

    mutating func value() throws(TOMLError) -> TOMLValue {
        guard !atEnd else { throw fail("expected a value") }
        switch c {
        case UInt8(ascii: "\""):
            if peek(1) == UInt8(ascii: "\""), peek(2) == UInt8(ascii: "\"") { return .string(try multilineBasic()) }
            return .string(try basicString())
        case UInt8(ascii: "'"):
            if peek(1) == UInt8(ascii: "'"), peek(2) == UInt8(ascii: "'") { return .string(try multilineLiteral()) }
            return .string(try literalString())
        case UInt8(ascii: "["): return try arrayValue()
        case UInt8(ascii: "{"): return try inlineTable()
        case UInt8(ascii: "t"), UInt8(ascii: "f"): return try boolValue()
        default: return try number()
        }
    }

    mutating func boolValue() throws(TOMLError) -> TOMLValue {
        if bytes[i...].starts(with: Array("true".utf8)) { i += 4; return .bool(true) }
        if bytes[i...].starts(with: Array("false".utf8)) { i += 5; return .bool(false) }
        throw fail("invalid value; strings must be quoted")
    }

    mutating func number() throws(TOMLError) -> TOMLValue {
        let start = i
        while !atEnd, !" \t\r\n,]}#".utf8.contains(c) { i += 1 }
        let raw = String(decoding: bytes[start..<i], as: UTF8.self)
        let text = raw.replacingOccurrences(of: "_", with: "")
        if text.isEmpty { throw fail("expected a value") }
        if text.count >= 10, text.dropFirst(4).first == "-", text.prefix(4).allSatisfy(\.isNumber) {
            throw fail("dates are not supported; quote '\(raw)' as a string")
        }
        if let n = Int(text) { return .int(n) }
        if text.hasPrefix("0x"), let n = Int(text.dropFirst(2), radix: 16) { return .int(n) }
        if text.contains(where: { ".eE".contains($0) }), let d = Double(text) { return .double(d) }
        throw fail("invalid value '\(raw)'; strings must be quoted")
    }

    mutating func arrayValue() throws(TOMLError) -> TOMLValue {
        i += 1
        var items: [TOMLValue] = []
        while true {
            skipBlank(newlines: true)
            if atEnd { throw fail("unterminated array") }
            if c == UInt8(ascii: "]") { i += 1; return .array(items) }
            items.append(try value())
            skipBlank(newlines: true)
            if c == UInt8(ascii: ",") { i += 1; continue }
            if c == UInt8(ascii: "]") { i += 1; return .array(items) }
            throw fail("expected ',' or ']' in array")
        }
    }

    mutating func inlineTable() throws(TOMLError) -> TOMLValue {
        i += 1
        var table = TOMLTable()
        skipBlank(newlines: false)
        if c == UInt8(ascii: "}") { i += 1; return .table(table) }
        while true {
            skipBlank(newlines: false)
            let keyLine = line
            let path = try keyPath()
            try expect("=")
            skipBlank(newlines: false)
            let v = try value()
            try withTable(Array(path.dropLast()), in: &table) { (t: inout TOMLTable) throws(TOMLError) in
                if t[path.last!] != nil { throw TOMLError(line: keyLine, message: "duplicate key '\(path.last!)'") }
                t.set(path.last!, v, line: keyLine)
            }
            skipBlank(newlines: false)
            if c == UInt8(ascii: ",") { i += 1; continue }
            if c == UInt8(ascii: "}") { i += 1; return .table(table) }
            throw fail("expected ',' or '}' in inline table")
        }
    }

    mutating func literalString() throws(TOMLError) -> String {
        i += 1
        let start = i
        while !atEnd, c != UInt8(ascii: "'") {
            if c == UInt8(ascii: "\n") { throw fail("unterminated string") }
            i += 1
        }
        guard !atEnd else { throw fail("unterminated string") }
        let s = String(decoding: bytes[start..<i], as: UTF8.self)
        i += 1
        return s
    }

    mutating func multilineLiteral() throws(TOMLError) -> String {
        i += 3
        if c == UInt8(ascii: "\n") { i += 1; line += 1 }
        let start = i
        while !atEnd {
            if c == UInt8(ascii: "'"), peek(1) == UInt8(ascii: "'"), peek(2) == UInt8(ascii: "'") {
                let s = String(decoding: bytes[start..<i], as: UTF8.self)
                i += 3
                return s
            }
            if c == UInt8(ascii: "\n") { line += 1 }
            i += 1
        }
        throw fail("unterminated multiline string")
    }

    mutating func basicString() throws(TOMLError) -> String {
        i += 1
        var out: [UInt8] = []
        while !atEnd {
            let b = c
            if b == UInt8(ascii: "\"") { i += 1; return String(decoding: out, as: UTF8.self) }
            if b == UInt8(ascii: "\n") { throw fail("unterminated string") }
            if b == UInt8(ascii: "\\") { try escape(into: &out); continue }
            out.append(b); i += 1
        }
        throw fail("unterminated string")
    }

    mutating func multilineBasic() throws(TOMLError) -> String {
        i += 3
        if c == UInt8(ascii: "\n") { i += 1; line += 1 }
        var out: [UInt8] = []
        while !atEnd {
            if c == UInt8(ascii: "\""), peek(1) == UInt8(ascii: "\""), peek(2) == UInt8(ascii: "\"") {
                i += 3
                return String(decoding: out, as: UTF8.self)
            }
            if c == UInt8(ascii: "\\") {
                // A backslash at the end of a line trims the newline and leading whitespace.
                var j = i + 1
                while j < bytes.count, bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t") || bytes[j] == UInt8(ascii: "\r") { j += 1 }
                if j < bytes.count, bytes[j] == UInt8(ascii: "\n") {
                    i = j
                    while !atEnd, " \t\r\n".utf8.contains(c) { if c == UInt8(ascii: "\n") { line += 1 }; i += 1 }
                    continue
                }
                try escape(into: &out)
                continue
            }
            if c == UInt8(ascii: "\n") { line += 1 }
            out.append(c); i += 1
        }
        throw fail("unterminated multiline string")
    }

    mutating func escape(into out: inout [UInt8]) throws(TOMLError) {
        i += 1
        let e = c
        i += 1
        switch e {
        case UInt8(ascii: "n"): out.append(0x0A)
        case UInt8(ascii: "t"): out.append(0x09)
        case UInt8(ascii: "r"): out.append(0x0D)
        case UInt8(ascii: "b"): out.append(0x08)
        case UInt8(ascii: "f"): out.append(0x0C)
        case UInt8(ascii: "e"): out.append(0x1B)
        case UInt8(ascii: "\""): out.append(0x22)
        case UInt8(ascii: "\\"): out.append(0x5C)
        case UInt8(ascii: "u"), UInt8(ascii: "U"):
            let n = e == UInt8(ascii: "u") ? 4 : 8
            guard i + n <= bytes.count,
                  let code = UInt32(String(decoding: bytes[i..<(i + n)], as: UTF8.self), radix: 16),
                  let scalar = Unicode.Scalar(code) else { throw fail("invalid unicode escape") }
            out.append(contentsOf: Array(String(Character(scalar)).utf8))
            i += n
        default:
            throw fail("invalid escape '\\\(Character(UnicodeScalar(e)))'")
        }
    }
}
