import AppKit
import KadomoMenuCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let launcher = Launcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One instance: if another copy already answers, ask it to open and leave.
        if let reply = try? Socket.exchange(path: Paths.socket, request: IPCRequest(args: ["ping"]), timeout: 1), reply.output == "pong" {
            _ = try? Socket.exchange(path: Paths.socket, request: IPCRequest(args: ["open"]), timeout: 2)
            Log.info("another instance is running; asked it to open")
            NSApp.terminate(nil)
            return
        }
        launcher.start()
        let ok = Socket.listen(path: Paths.socket) { [launcher] request in await launcher.handle(request) }
        if !ok { Log.error("the CLI socket could not start; `kadomo-menu` commands will not reach this app") }
    }

    /// Double-clicking the app while it runs opens the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        launcher.flushUsage()
        unlink(Paths.socket)
    }
}
