import Foundation
import KadomoMenuCore

/// A Unix domain socket only this user can open. The app listens; the CLI
/// connects, writes one JSON line, and reads one JSON line back.
nonisolated enum Socket {
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    // MARK: App side

    /// Starts listening on a background thread. `handle` runs on the main actor.
    /// Returns false when the socket cannot be created.
    static func listen(path: String, handle: @escaping @MainActor @Sendable (IPCRequest) async -> IPCResponse) -> Bool {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0, var address = address(path) else { return false }
        // Create the socket file owner-only, so there is no window before the chmod below.
        let previousMask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(previousMask)
        guard bound == 0, Darwin.listen(server, 16) == 0 else {
            Log.error("could not listen on \(path): \(String(cString: strerror(errno)))")
            close(server)
            return false
        }
        chmod(path, 0o600)
        Thread.detachNewThread {
            while true {
                let client = accept(server, nil, nil)
                guard client >= 0 else {
                    // A persistent error (out of descriptors, say) must not spin a core.
                    if errno != EINTR { usleep(100_000) }
                    continue
                }
                var noSigPipe: Int32 = 1
                setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                var timeout = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let data = readLine(client)
                Task { @MainActor in
                    let response: IPCResponse
                    if let request = IPCCodec.decode(IPCRequest.self, data) {
                        response = await handle(request)
                    } else {
                        response = .fail("malformed request", status: 2)
                    }
                    let out = IPCCodec.encode(response)
                    DispatchQueue.global().async {
                        write(client, out)
                        close(client)
                    }
                }
            }
        }
        return true
    }

    // MARK: CLI side

    static func exchange(path: String, request: IPCRequest, timeout: Int = 60) throws -> IPCResponse {
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0, var address = address(path) else { throw SocketError.unavailable }
        defer { close(client) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw SocketError.unavailable }
        write(client, IPCCodec.encode(request))
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let data = readLine(client, timeout: timeout)
        guard let response = IPCCodec.decode(IPCResponse.self, data) else {
            throw data.isEmpty ? SocketError.timedOut : SocketError.badReply
        }
        return response
    }

    /// `unavailable`: nothing is listening. `timedOut`: connected, but no answer came back.
    enum SocketError: Error { case unavailable, timedOut, badReply }

    // MARK: Bytes

    // Bound both memory and total time, even when a peer keeps sending bytes.
    static let maxMessageBytes = 4 * 1024 * 1024

    static func readLine(_ socket: Int32, timeout: Int = 5) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeout)
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return Data() }
            var descriptor = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return Data() }
            let count = read(socket, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0, data.count + count <= maxMessageBytes else { return Data() }
            data.append(buffer, count: count)
            if buffer[count - 1] == 0x0A { return data }
        }
    }

    static func write(_ socket: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.write(socket, raw.baseAddress! + offset, raw.count - offset)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }
}
