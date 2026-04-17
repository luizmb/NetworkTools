import Testing
import Foundation
@testable import HTMLTemplating

// MARK: - Helpers

@discardableResult
private func withFragmentDir<T>(
    _ fragments: [String: String],
    body: (HTMLEnvironment) throws -> T
) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    for (name, content) in fragments {
        try content.write(
            to: dir.appendingPathComponent("\(name).html.template"),
            atomically: true,
            encoding: .utf8
        )
    }
    return try body(HTMLEnvironment.live(path: dir.path))
}

// MARK: - esc / escAttr

@Suite("esc")
struct EscTests {
    @Test func ampersand()    { #expect(esc("a&b") == "a&amp;b") }
    @Test func lessThan()     { #expect(esc("<x>") == "&lt;x&gt;") }
    @Test func greaterThan()  { #expect(esc("x>y") == "x&gt;y") }
    @Test func noSpecials()   { #expect(esc("hello") == "hello") }
    @Test func combined()     { #expect(esc("<a&b>") == "&lt;a&amp;b&gt;") }
    @Test func empty()        { #expect(esc("") == "") }
}

@Suite("escAttr")
struct EscAttrTests {
    @Test func quote() { #expect(escAttr(#"say "hi""#) == "say &quot;hi&quot;") }
    @Test func combined() {
        #expect(escAttr(#"<a href="url">"#) == "&lt;a href=&quot;url&quot;&gt;")
    }
    @Test func noSpecials() { #expect(escAttr("hello") == "hello") }
}

// MARK: - render: plain substitution

@Suite("render — substitution")
struct RenderSubstitutionTests {
    private let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))

    @Test func stringVariable() throws {
        let out = try render("Hello {{name}}!", ["name": .string("World")]).runReader(env).get()
        #expect(out == "Hello World!")
    }

    @Test func boolTrue() throws {
        let out = try render("{{v}}", ["v": .bool(true)]).runReader(env).get()
        #expect(out == "true")
    }

    @Test func boolFalse() throws {
        let out = try render("{{v}}", ["v": .bool(false)]).runReader(env).get()
        #expect(out == "false")
    }

    @Test func missingKeyIsEmpty() throws {
        let out = try render("{{missing}}", [:]).runReader(env).get()
        #expect(out == "")
    }

    @Test func listValueIgnored() throws {
        let out = try render("{{items}}", ["items": .list([["x": .string("1")]])]).runReader(env).get()
        #expect(out == "")
    }

    @Test func noTokens() throws {
        let out = try render("plain text", [:]).runReader(env).get()
        #expect(out == "plain text")
    }

    @Test func unclosedBracePassthrough() throws {
        let out = try render("{{unclosed", [:]).runReader(env).get()
        #expect(out == "{{unclosed")
    }

    @Test func multipleVariables() throws {
        let out = try render("{{a}} {{b}}", ["a": .string("foo"), "b": .string("bar")]).runReader(env).get()
        #expect(out == "foo bar")
    }

    @Test func whitespaceAroundKey() throws {
        let out = try render("{{ name }}", ["name": .string("trimmed")]).runReader(env).get()
        #expect(out == "trimmed")
    }

    @Test func emptyTemplate() throws {
        let out = try render("", [:]).runReader(env).get()
        #expect(out == "")
    }

    @Test func surroundingText() throws {
        let out = try render("<p>{{x}}</p>", ["x": .string("hi")]).runReader(env).get()
        #expect(out == "<p>hi</p>")
    }
}

// MARK: - render: #each

@Suite("render — #each")
struct RenderEachTests {
    @Test func rendersAllItems() throws {
        try withFragmentDir(["row": "<li>{{name}}</li>"]) { env in
            let ctx: Context = ["items": .list([["name": .string("A")], ["name": .string("B")]])]
            let out = try render("{{#each items row}}", ctx).runReader(env).get()
            #expect(out == "<li>A</li><li>B</li>")
        }
    }

    @Test func emptyListProducesEmpty() throws {
        try withFragmentDir(["row": "<li>{{x}}</li>"]) { env in
            let out = try render("{{#each items row}}", ["items": .list([])]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func missingContextKeySkipped() throws {
        try withFragmentDir(["row": "<li/>"]) { env in
            let out = try render("{{#each missing row}}", [:]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func nonListValueSkipped() throws {
        try withFragmentDir(["row": "<li/>"]) { env in
            let out = try render("{{#each s row}}", ["s": .string("not a list")]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let ctx: Context = ["items": .list([["name": .string("A")]])]
        let result = render("{{#each items missing}}", ctx).runReader(env)
        guard case .failure = result else {
            Issue.record("Expected .failure for missing fragment")
            return
        }
    }

    @Test func itemContextIsolated() throws {
        try withFragmentDir(["row": "{{val}}"]) { env in
            let ctx: Context = [
                "val":   .string("outer"),
                "items": .list([["val": .string("inner")]]),
            ]
            let out = try render("{{#each items row}}", ctx).runReader(env).get()
            #expect(out == "inner")
        }
    }
}

// MARK: - render: #if

@Suite("render — #if")
struct RenderIfTests {
    @Test func trueBoolShowsFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", ["flag": .bool(true)]).runReader(env).get()
            #expect(out == "<p>shown</p>")
        }
    }

    @Test func falseBoolHidesFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", ["flag": .bool(false)]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func missingKeyHidesFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", [:]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func nonEmptyStringIsTruthy() throws {
        try withFragmentDir(["yes": "X"]) { env in
            let out = try render("{{#if s yes}}", ["s": .string("hello")]).runReader(env).get()
            #expect(out == "X")
        }
    }

    @Test func emptyStringIsFalsy() throws {
        try withFragmentDir(["yes": "X"]) { env in
            let out = try render("{{#if s yes}}", ["s": .string("")]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func nonEmptyListIsTruthy() throws {
        try withFragmentDir(["yes": "Y"]) { env in
            let ctx: Context = ["items": .list([["k": .string("v")]])]
            let out = try render("{{#if items yes}}", ctx).runReader(env).get()
            #expect(out == "Y")
        }
    }

    @Test func emptyListIsFalsy() throws {
        try withFragmentDir(["yes": "Y"]) { env in
            let out = try render("{{#if items yes}}", ["items": .list([])]).runReader(env).get()
            #expect(out == "")
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let result = render("{{#if flag missing}}", ["flag": .bool(true)]).runReader(env)
        guard case .failure = result else {
            Issue.record("Expected .failure for missing fragment")
            return
        }
    }
}

// MARK: - render: #include

@Suite("render — #include")
struct RenderIncludeTests {
    @Test func insertsFragment() throws {
        try withFragmentDir(["header": "<h1>Title</h1>"]) { env in
            let out = try render("{{#include header}}", [:]).runReader(env).get()
            #expect(out == "<h1>Title</h1>")
        }
    }

    @Test func fragmentReceivesContext() throws {
        try withFragmentDir(["greeting": "Hello {{name}}"]) { env in
            let out = try render("{{#include greeting}}", ["name": .string("World")]).runReader(env).get()
            #expect(out == "Hello World")
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let result = render("{{#include missing}}", [:]).runReader(env)
        if case .failure(let e) = result, case .readError(let name, _) = e {
            #expect(name == "missing")
        } else {
            Issue.record("Expected .failure(.readError(\"missing\", _)), got \(result)")
        }
    }

    @Test func textBeforeAndAfterFragment() throws {
        try withFragmentDir(["nav": "<nav/>"]) { env in
            let out = try render("before{{#include nav}}after", [:]).runReader(env).get()
            #expect(out == "before<nav/>after")
        }
    }
}

// MARK: - render: nesting & Reader

@Suite("render — composition")
struct RenderCompositionTests {
    @Test func nestedIncludes() throws {
        try withFragmentDir([
            "outer": "<outer>{{#include inner}}</outer>",
            "inner": "<inner>{{val}}</inner>",
        ]) { env in
            let out = try render("{{#include outer}}", ["val": .string("X")]).runReader(env).get()
            #expect(out == "<outer><inner>X</inner></outer>")
        }
    }

    @Test func readerEnvironmentSelectsFragmentDirectory() throws {
        let a = try withFragmentDir(["g": "Hello"]) { env in
            try render("{{#include g}}", [:]).runReader(env).get()
        }
        let b = try withFragmentDir(["g": "Goodbye"]) { env in
            try render("{{#include g}}", [:]).runReader(env).get()
        }
        #expect(a == "Hello")
        #expect(b == "Goodbye")
    }

    @Test func eachInsideInclude() throws {
        try withFragmentDir([
            "list": "<ul>{{#each items row}}</ul>",
            "row":  "<li>{{name}}</li>",
        ]) { env in
            let ctx: Context = ["items": .list([["name": .string("A")], ["name": .string("B")]])]
            let out = try render("{{#include list}}", ctx).runReader(env).get()
            #expect(out == "<ul><li>A</li><li>B</li></ul>")
        }
    }

    @Test func errorInNestedFragmentPropagates() throws {
        try withFragmentDir(["outer": "{{#include inner}}"]) { env in
            let result = render("{{#include outer}}", [:]).runReader(env)
            guard case .failure = result else {
                Issue.record("Expected failure when nested fragment is missing")
                return
            }
        }
    }
}

// MARK: - loadTemplate

@Suite("loadTemplate")
struct LoadTemplateTests {
    @Test func notFoundReturnsFailure() {
        let result = loadTemplate("nonexistent", in: .main)
        guard case .failure(let e) = result, case .notFound = e else {
            Issue.record("Expected .failure(.notFound), got \(result)")
            return
        }
    }
}
