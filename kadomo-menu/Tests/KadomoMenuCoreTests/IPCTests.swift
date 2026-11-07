import Testing
@testable import KadomoMenuCore

@Suite struct IPCTests {
    @Test func printableOutputReplacesControlCharacters() {
        let title = IPCResponse.ok("a\u{1B}]0;title\u{07}b")
        #expect(title.printableOutput == "a?]0;title?b")
        #expect(IPCResponse.ok("\u{9B}31m\u{7F}\r").printableOutput == "?31m??")
    }

    @Test func printableOutputKeepsLayoutAndUnicode() {
        let text = "東京 café\tid\nnext · line"
        #expect(IPCResponse.ok(text).printableOutput == text)
    }
}
