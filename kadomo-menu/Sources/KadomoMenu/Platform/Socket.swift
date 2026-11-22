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
        guard var address = address(path) else { return false }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK, existing.st_uid == geteuid(), unlink(path) == 0 else { return false }
        }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else { return false }
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
        let slots = DispatchSemaphore(value: 16)
        Thread.detachNewThread {
            while true {
                slots.wait()
                let client = accept(server, nil, nil)
                guard client >= 0 else {
                    slots.signal()
                    // A persistent error (out of descriptors, say) must not spin a core.
                    if errno != EINTR { usleep(100_000) }
                    continue
                }
                DispatchQueue.global().async {
                    guard sameUser(client) else {
                        close(client)
                        slots.signal()
                        return
                    }
                    let request = IPCCodec.decode(IPCRequest.self, readLine(client))
                    Task { @MainActor in
                        let response: IPCResponse
                        if let request {
                            response = await handle(request)
                        } else {
                            response = .fail("malformed request", status: 2)
                        }
                        let out = IPCCodec.encode(response)
                        DispatchQueue.global().async {
                            write(client, out)
                            close(client)
                            slots.signal()
                        }
                    }
                }
            }
        }
        return true
    }

    // MARK: CLI side

    static func exchange(path: String, request: IPCRequest, timeout: Int = 60) throws -> IPCResponse {
        guard var address = address(path) else { throw SocketError.unavailable }
        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        guard client >= 0 else { throw SocketError.unavailable }
        defer { close(client) }
        guard makeNonblocking(client) else { throw SocketError.unavailable }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            switch errno {
            case EINPROGRESS, EINTR:
                let deadline = ProcessInfo.processInfo.systemUptime + Double(min(timeout, 5))
                guard ready(client, event: Int16(POLLOUT), deadline: deadline) else { throw SocketError.timedOut }
                var error: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(client, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else {
                    throw SocketError.unavailable
                }
            case EAGAIN, EWOULDBLOCK:
                throw SocketError.timedOut
            default:
                throw SocketError.unavailable
            }
        }
        guard sameUser(client) else { throw SocketError.unavailable }
        guard write(client, IPCCodec.encode(request), timeout: min(timeout, 5)) else { throw SocketError.timedOut }
        let data = readLine(client, timeout: timeout)
        guard let response = IPCCodec.decode(IPCResponse.self, data) else {
            throw data.isEmpty ? SocketError.timedOut : SocketError.badReply
        }
        return response
    }

    /// `unavailable`: nothing is listening. `timedOut`: connected, but no answer came back.
    enum SocketError: Error { case unavailable, timedOut, badReply }

    private static func sameUser(_ socket: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(socket, &uid, &gid) == 0 && uid == geteuid()
    }

    // MARK: Bytes

    // Bound both memory and total time, even when a peer keeps sending bytes.
    static let maxMessageBytes = 4 * 1024 * 1024

    static func readLine(_ socket: Int32, timeout: Int = 5) -> Data {
        guard makeNonblocking(socket) else { return Data() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeout)
        while ready(socket, event: Int16(POLLIN), deadline: deadline) {
            let count = read(socket, &buffer, buffer.count)
            if count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
            guard count > 0, data.count + count <= maxMessageBytes else { return Data() }
            data.append(buffer, count: count)
            if buffer[count - 1] == 0x0A { return data }
        }
        return Data()
    }

    private static func makeNonblocking(_ socket: Int32) -> Bool {
        let flags = fcntl(socket, F_GETFL)
        return flags >= 0 && fcntl(socket, F_SETFL, flags | O_NONBLOCK) == 0
    }

    private static func ready(_ socket: Int32, event: Int16, deadline: TimeInterval) -> Bool {
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return false }
            var descriptor = pollfd(fd: socket, events: event, revents: 0)
            let count = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
            if count < 0 && errno == EINTR { continue }
            return count > 0 && descriptor.revents & event != 0
        }
    }

    @discardableResult
    static func write(_ socket: Int32, _ data: Data, timeout: Int = 5) -> Bool {
        var noSigPipe: Int32 = 1
        guard makeNonblocking(socket),
              setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeout)
        return data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                guard ready(socket, event: Int16(POLLOUT), deadline: deadline) else { return false }
                let sent = Darwin.write(socket, raw.baseAddress! + offset, raw.count - offset)
                if sent < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) { continue }
                guard sent > 0 else { return false }
                offset += sent
            }
            return true
        }
    }
}
