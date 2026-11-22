import AppKit
import KadomoMenuCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let launcher = Launcher()
    private var listening = false
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance: if another copy already answers, ask it to open and leave.
        do {
            let reply = try Socket.exchange(path: Paths.socket, request: IPCRequest(args: ["ping"]), timeout: 1)
            if reply.output == "pong" {
                _ = try? Socket.exchange(path: Paths.socket, request: IPCRequest(args: ["open"]), timeout: 2)
            }
            NSApp.terminate(nil)
            return
        } catch Socket.SocketError.unavailable {
            // A missing or stale socket can be replaced.
        } catch {
            Log.error("another launcher accepted the connection but did not answer the ping")
            NSApp.terminate(nil)
            return
        }
        listening = Socket.listen(path: Paths.socket) { [launcher] request in await launcher.handle(request) }
        launcher.start()
        started = true
        if !listening { Log.error("the CLI socket could not start; `kadomo-menu` commands will not reach this app") }
    }

    /// Double-clicking the app while it runs opens the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if started { launcher.flushUsage() }
        if listening { unlink(Paths.socket) }
    }
}
