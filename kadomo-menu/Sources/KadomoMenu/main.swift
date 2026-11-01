import AppKit
import KadomoMenuCore

// One binary, two roles. Invoked as `kadomo-menu` (the symlink build.sh
// installs) or with a command argument, it is the CLI. Otherwise it is the
// resident launcher.
// A peer that hangs up mid-reply must not kill either side; writes fail with EPIPE instead.
signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
let invokedName = (arguments[0] as NSString).lastPathComponent
let environment = ProcessInfo.processInfo.environment
let wantsCLI = environment["KADOMO_MENU_GUI"] == nil
    && (invokedName == "kadomo-menu" || (arguments.count > 1 && !arguments[1].hasPrefix("-")))

if wantsCLI {
    exit(CLI.run(Array(arguments.dropFirst())))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let dir = environment["KADOMO_MENU_SNAPSHOT"] {
    Snapshot.run(to: dir)
    exit(0)
}

if environment["KADOMO_MENU_PROFILE"] == "1" {
    Task { exit(await Profile.run()) }
    RunLoop.main.run()
}

if environment["KADOMO_MENU_SELFTEST"] == "1" {
    Task { exit(await SelfTest.run()) }
    RunLoop.main.run()
}

// Headless: the launcher and its socket without the AppKit event loop, for
// scripted checks of the CLI protocol (tools/check-cli.sh).
if environment["KADOMO_MENU_HEADLESS"] == "1" {
    let launcher = Launcher()
    launcher.start(interactive: false)
    _ = Socket.listen(path: Paths.socket) { request in await launcher.handle(request) }
    RunLoop.main.run()
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
