import Foundation
import Testing
@testable import KadomoMenu

private func pair() throws -> [Int32] {
    var fds: [Int32] = [-1, -1]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    var enabled: Int32 = 1
    setsockopt(fds[1], SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
    return fds
}

@Test func socketAcceptsCompleteMessage() throws {
    let fds = try pair()
    defer { close(fds[0]); close(fds[1]) }
    let message = Data("{\"args\":[]}\n".utf8)
    Socket.write(fds[1], message)
    #expect(Socket.readLine(fds[0]) == message)
}

@Test func socketRejectsOversizedMessage() throws {
    let fds = try pair()
    defer { close(fds[0]) }
    let writer = fds[1]
    Thread.detachNewThread {
        defer { close(writer) }
        Socket.write(writer, Data(repeating: 65, count: Socket.maxMessageBytes + 1))
    }
    #expect(Socket.readLine(fds[0]).isEmpty)
}

@Test func socketDeadlineStopsContinuousInput() throws {
    let fds = try pair()
    defer { close(fds[0]) }
    let writer = fds[1]
    Thread.detachNewThread {
        defer { close(writer) }
        var byte: UInt8 = 65
        while Darwin.write(writer, &byte, 1) == 1 { usleep(10_000) }
    }
    let start = ProcessInfo.processInfo.systemUptime
    #expect(Socket.readLine(fds[0], timeout: 1).isEmpty)
    #expect(ProcessInfo.processInfo.systemUptime - start < 3)
}

@Test func socketWriteReturnsAtItsDeadline() throws {
    let fds = try pair()
    defer { close(fds[0]); close(fds[1]) }
    var sendBuffer: Int32 = 4096
    #expect(setsockopt(fds[1], SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size)) == 0)
    let start = ProcessInfo.processInfo.systemUptime
    #expect(!Socket.write(fds[1], Data(repeating: 65, count: 256 * 1024), timeout: 1))
    #expect(ProcessInfo.processInfo.systemUptime - start < 3)
}
