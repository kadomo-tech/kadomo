import Foundation

/// One request per connection over a Unix socket that only this user can
/// open: the CLI writes a JSON line, the app answers with one JSON line.
public struct IPCRequest: Codable, Sendable, Equatable {
    public var args: [String]
    public init(args: [String]) { self.args = args }
}

public struct IPCResponse: Codable, Sendable, Equatable {
    /// Process exit status for the CLI: 0 ok, 1 failure, 2 usage error.
    public var status: Int32
    public var output: String
    public init(status: Int32 = 0, output: String = "") {
        self.status = status
        self.output = output
    }
    public static func ok(_ s: String = "") -> IPCResponse { IPCResponse(status: 0, output: s) }
    public static func fail(_ s: String, status: Int32 = 1) -> IPCResponse { IPCResponse(status: status, output: s) }
}

public enum IPCCodec {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        var data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        let trimmed = data.last == 0x0A ? data.dropLast() : data[...]
        return try? JSONDecoder().decode(type, from: Data(trimmed))
    }
}
