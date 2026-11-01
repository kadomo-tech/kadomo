import Testing
@testable import KadomoMenuCore

@Suite struct TOMLTests {
    @Test func parsesScalarsAndTables() throws {
        let t = try TOML.parse("""
        # comment
        name = "Kadomo" # trailing
        count = 1_000
        ratio = 0.5
        on = true
        list = ["a", 'b', ]
        [geometry]
        width = 600
        [colors.light]
        background = "#fff"
        inline = { a = 1, b.c = "x" }
        """)
        #expect(t["name"]?.string == "Kadomo")
        #expect(t["count"]?.int == 1000)
        #expect(t["ratio"]?.double == 0.5)
        #expect(t["on"]?.bool == true)
        #expect(t["list"]?.array?.compactMap(\.string) == ["a", "b"])
        #expect(t["geometry"]?.table?["width"]?.int == 600)
        let light = t["colors"]?.table?["light"]?.table
        #expect(light?["background"]?.string == "#fff")
        #expect(light?["inline"]?.table?["b"]?.table?["c"]?.string == "x")
        #expect(t.line(of: "name") == 2)
    }

    @Test func arraysOfTablesAndSubtables() throws {
        let t = try TOML.parse("""
        [[command]]
        title = "One"
        [[command.action]]
        title = "A"
        [[command]]
        title = "Two"
        """)
        let cmds = t["command"]?.array ?? []
        #expect(cmds.count == 2)
        #expect(cmds[0].table?["action"]?.array?.first?.table?["title"]?.string == "A")
        #expect(cmds[1].table?["title"]?.string == "Two")
    }

    @Test func stringEscapesAndMultiline() throws {
        let t = try TOML.parse(#"""
        a = "tab\tquote\"unié"
        b = """
        line1
        line2\
           joined"""
        c = '''raw\n'''
        "quoted key" = 1
        """#)
        #expect(t["a"]?.string == "tab\tquote\"unié")
        #expect(t["b"]?.string == "line1\nline2joined")
        #expect(t["c"]?.string == "raw\\n")
        #expect(t["quoted key"]?.int == 1)
    }

    @Test(arguments: [
        ("a = ", 1, "expected a value"),
        ("a = 1\na = 2", 2, "duplicate key 'a'"),
        ("a = \"open", 1, "unterminated string"),
        ("[t]\nx = 1\n[t.x]", 3, "'x' is a value, not a table"),
        ("d = 2024-01-01", 1, "dates are not supported"),
        ("bare = hello", 1, "strings must be quoted"),
    ])
    func reportsErrorsWithLines(_ text: String, line: Int, message: String) {
        do {
            _ = try TOML.parse(text)
            Issue.record("expected an error")
        } catch {
            #expect(error.line == line)
            #expect(error.message.contains(message), "\(error.message)")
        }
    }

    @Test func unicodeAndBOM() throws {
        let t = try TOML.parse("\u{FEFF}title = \"東京 café\"")
        #expect(t["title"]?.string == "東京 café")
    }
}
