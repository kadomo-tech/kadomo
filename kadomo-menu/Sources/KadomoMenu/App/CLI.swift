import Foundation
import KadomoMenuCore

/// The `kadomo-menu` command line. Most commands go to the running app over
/// its socket; `config check`, `help`, and the search benchmark run locally.
enum CLI {
    static let help = """
    kadomo-menu — keyboard-first launcher for macOS

    USAGE
      kadomo-menu <command> [options]

    LAUNCHER
      open [--category <id>] [--query <text>]   Show the launcher (starts the app if needed)
      toggle                                    Show or hide
      close                                     Hide
      reload                                    Re-read config, themes, commands, and apps
      status                                    Hotkey, theme, item counts, memory, timings, problems
      quit                                      Stop the background app

    THEMES
      theme list                                All themes; * marks the current one
      theme current                             Print the current theme id
      theme set <name>                          Switch live and save to config.toml

    COMMANDS
      commands list [--json] [--categories] [--category <id>]
      commands run <id> [--yes]                 Run any item by id (--yes for confirmed items)

    CONFIGURATION
      config check                              Validate config, themes, and commands (exit 1 on errors)
      config path                               Print the config, theme, command, and state paths

    DIAGNOSTICS
      benchmark [--count N] [--rounds N] [--ui N] [--search-only]
      login on|off|status                       Launch at login
      version
    """

    static func run(_ args: [String]) -> Int32 {
        guard let command = args.first else { print(help); return 0 }
        switch command {
        case "help", "-h", "--help":
            print(help)
            return 0
        case "version", "--version", "-v":
            print("kadomo-menu \(Launcher.version)")
            return 0
        case "config":
            return config(Array(args.dropFirst()))
        case "benchmark":
            return benchmark(Array(args.dropFirst()))
        case "open", "toggle":
            return send(args, launch: true)
        default:
            return send(args, launch: false)
        }
    }

    static func send(_ args: [String], launch: Bool) -> Int32 {
        let request = IPCRequest(args: args)
        do {
            let response = try exchange(request, launch: launch)
            if !response.output.isEmpty {
                let out = response.status == 0 ? FileHandle.standardOutput : FileHandle.standardError
                out.write(Data((response.output + "\n").utf8))
            }
            return response.status
        } catch Socket.SocketError.timedOut {
            FileHandle.standardError.write(Data("kadomo-menu: the launcher did not answer within 60 s. It may still be running the command.\n".utf8))
            return 1
        } catch Socket.SocketError.badReply {
            FileHandle.standardError.write(Data("kadomo-menu: the launcher sent a reply this version cannot read.\n".utf8))
            return 1
        } catch {
            FileHandle.standardError.write(Data("kadomo-menu: the launcher is not running. Start it with `kadomo-menu open` or open KadomoMenu.app.\n".utf8))
            return 1
        }
    }

    /// Starts the app and retries only when nothing is listening. A launcher that
    /// accepted the request but answered late already acted on it, so it is not resent.
    static func exchange(_ request: IPCRequest, launch: Bool, timeout: Int = 60) throws -> IPCResponse {
        do {
            return try Socket.exchange(path: Paths.socket, request: request, timeout: timeout)
        } catch Socket.SocketError.unavailable where launch {
            startApp()
        }
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.1)
            do {
                return try Socket.exchange(path: Paths.socket, request: request, timeout: timeout)
            } catch Socket.SocketError.unavailable {
                continue
            }
        }
        throw Socket.SocketError.unavailable
    }

    /// Starts the app bundle this binary lives in, in the background.
    static func startApp() {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        if bundle.pathExtension == "app" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", bundle.path]
        } else {
            process.executableURL = exe
            process.arguments = []
            process.environment = ProcessInfo.processInfo.environment.merging(["KADOMO_MENU_GUI": "1"]) { $1 }
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: config

    static func config(_ args: [String]) -> Int32 {
        switch args.first ?? "check" {
        case "path":
            print("""
            config    \(Paths.configFile)
            themes    \(Paths.themesDirectory)
            commands  \(Paths.commandsDirectory)
            state     \(Paths.stateDirectory)
            socket    \(Paths.socket)
            """)
            return 0
        case "check":
            let store = MainActor.assumeIsolated { () -> ConfigStore in
                let s = ConfigStore()
                s.load()
                return s
            }
            let (theme, themeDiags) = MainActor.assumeIsolated { store.resolveTheme() }
            let diags = MainActor.assumeIsolated { store.diagnostics } + themeDiags
            for d in diags { print(d) }
            let errors = diags.filter { $0.severity == .error }.count
            let warnings = diags.count - errors
            let commands = MainActor.assumeIsolated { store.userItems.filter { $0.kind != .category }.count }
            print("\(errors == 0 ? "OK" : "FAILED"): \(errors) errors, \(warnings) warnings · theme \(theme?.name ?? "invalid") · \(commands) user commands")
            return errors == 0 ? 0 : 1
        default:
            FileHandle.standardError.write(Data("usage: kadomo-menu config check|path\n".utf8))
            return 2
        }
    }

    // MARK: benchmark

    static func benchmark(_ args: [String]) -> Int32 {
        func value(_ name: String, _ fallback: Int) -> Int {
            guard let i = args.firstIndex(of: name), i + 1 < args.count, let n = Int(args[i + 1]) else { return fallback }
            return n
        }
        let count = value("--count", 10_000)
        let rounds = value("--rounds", 50)
        let uiRounds = value("--ui", 100)

        print("kadomo-menu \(Launcher.version) benchmark")
        print("machine   \(sysctlString("hw.model")) · \(sysctlString("machdep.cpu.brand_string")) · \(ProcessInfo.processInfo.processorCount) cores · \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")
        print("system    macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if DEBUG
        print("build     DEBUG (numbers are pessimistic; use a release build)")
        #else
        print("build     release")
        #endif
        print("")
        let r = SearchBenchmark.run(count: count, rounds: rounds)
        print("search    \(r.items) items, \(SyntheticRegistry.queries.count) queries × \(rounds) rounds")
        print(String(format: "  index build           %.1f ms", r.buildMilliseconds))
        print("  index search          \(r.search)")
        print("  model (scope+rank)    \(r.model)")

        guard !args.contains("--search-only") else { return 0 }
        print("")
        guard let ui = try? exchange(IPCRequest(args: ["bench-ui", String(uiRounds)]), launch: false, timeout: 600),
              let before = try? exchange(IPCRequest(args: ["status"]), launch: false) else {
            print("ui        skipped: the launcher is not running (start it, then run again)")
            return 0
        }
        print("ui        running app, \(uiRounds) open/type/close cycles (the panel flashes on screen)")
        print(ui.output.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n"))
        print("")
        // Idle: CPU time consumed over 10 s with nothing happening.
        let cpu0 = cpuSeconds(in: before.output)
        Thread.sleep(forTimeInterval: 10)
        if let after = try? exchange(IPCRequest(args: ["status"]), launch: false) {
            let cpu1 = cpuSeconds(in: after.output)
            let mem = after.output.split(separator: "\n").first { $0.hasPrefix("Memory:") } ?? ""
            print(String(format: "idle      %.3f%% CPU over 10 s (includes answering this status request)", max(0, (cpu1 - cpu0) / 10 * 100)))
            print("          \(mem)")
            for line in after.output.split(separator: "\n") where line.hasPrefix("Cold start") || line.hasPrefix("Hotkey →") || line.hasPrefix("Items:") {
                print("          \(line)")
            }
        }
        return 0
    }

    static func cpuSeconds(in status: String) -> Double {
        guard let line = status.split(separator: "\n").first(where: { $0.hasPrefix("Memory:") }),
              let range = line.range(of: "CPU time ") else { return 0 }
        return Double(line[range.upperBound...].split(separator: " ").first ?? "") ?? 0
    }

    static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
