// SPDX-License-Identifier: Apache-2.0

// swiftlint:disable file_length
import Foundation
import FP
@testable import HTMLTemplating
import Testing

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
            to: dir.appendingPathComponent("\(name).template"),
            atomically: true,
            encoding: .utf8
        )
    }
    return try body(HTMLEnvironment.live(path: dir.path))
}

// MARK: - esc / escAttr

@Suite("esc")
struct EscTests {
    @Test func ampersand() { #expect(esc("a&b") == "a&amp;b") }
    @Test func lessThan() { #expect(esc("<x>") == "&lt;x&gt;") }
    @Test func greaterThan() { #expect(esc("x>y") == "x&gt;y") }
    @Test func noSpecials() { #expect(esc("hello") == "hello") }
    @Test func combined() { #expect(esc("<a&b>") == "&lt;a&amp;b&gt;") }
    @Test func empty() { #expect(esc("").isEmpty) }
    @Test func multiByteTextIsKept() { #expect(esc("café <ü> 🎉&") == "café &lt;ü&gt; 🎉&amp;") }
    @Test func quotesAreKept() { #expect(esc(#""q""#) == #""q""#) }
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
        let out = try render("Hello {{name}}!", ["name": .string("World")]).rawValue.runReader(env).get()
        #expect(out == "Hello World!")
    }

    @Test func boolTrue() throws {
        let out = try render("{{v}}", ["v": .bool(true)]).rawValue.runReader(env).get()
        #expect(out == "true")
    }

    @Test func boolFalse() throws {
        let out = try render("{{v}}", ["v": .bool(false)]).rawValue.runReader(env).get()
        #expect(out == "false")
    }

    @Test func missingKeyIsEmpty() throws {
        let out = try render("{{missing}}", [:]).rawValue.runReader(env).get()
        #expect(out.isEmpty)
    }

    @Test func listValueIgnored() throws {
        let out = try render("{{items}}", ["items": .list([["x": .string("1")]])]).rawValue.runReader(env).get()
        #expect(out.isEmpty)
    }

    @Test func noTokens() throws {
        let out = try render("plain text", [:]).rawValue.runReader(env).get()
        #expect(out == "plain text")
    }

    @Test func unclosedBracePassthrough() throws {
        let out = try render("{{unclosed", [:]).rawValue.runReader(env).get()
        #expect(out == "{{unclosed")
    }

    @Test func multipleVariables() throws {
        let out = try render("{{a}} {{b}}", ["a": .string("foo"), "b": .string("bar")]).rawValue.runReader(env).get()
        #expect(out == "foo bar")
    }

    @Test func whitespaceAroundKey() throws {
        let out = try render("{{ name }}", ["name": .string("trimmed")]).rawValue.runReader(env).get()
        #expect(out == "trimmed")
    }

    @Test func emptyTemplate() throws {
        let out = try render("", [:]).rawValue.runReader(env).get()
        #expect(out.isEmpty)
    }

    @Test func surroundingText() throws {
        let out = try render("<p>{{x}}</p>", ["x": .string("hi")]).rawValue.runReader(env).get()
        #expect(out == "<p>hi</p>")
    }
}

// MARK: - render: #each

@Suite("render — #each")
struct RenderEachTests {
    @Test func rendersAllItems() throws {
        try withFragmentDir(["row": "<li>{{name}}</li>"]) { env in
            let ctx: Context = ["items": .list([["name": .string("A")], ["name": .string("B")]])]
            let out = try render("{{#each items row}}", ctx).rawValue.runReader(env).get()
            #expect(out == "<li>A</li><li>B</li>")
        }
    }

    @Test func emptyListProducesEmpty() throws {
        try withFragmentDir(["row": "<li>{{x}}</li>"]) { env in
            let out = try render("{{#each items row}}", ["items": .list([])]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func missingContextKeySkipped() throws {
        try withFragmentDir(["row": "<li/>"]) { env in
            let out = try render("{{#each missing row}}", [:]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func nonListValueSkipped() throws {
        try withFragmentDir(["row": "<li/>"]) { env in
            let out = try render("{{#each s row}}", ["s": .string("not a list")]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let ctx: Context = ["items": .list([["name": .string("A")]])]
        let result = render("{{#each items missing}}", ctx).rawValue.runReader(env)
        guard case .failure = result else {
            Issue.record("Expected .failure for missing fragment")
            return
        }
    }

    @Test func itemContextIsolated() throws {
        try withFragmentDir(["row": "{{val}}"]) { env in
            let ctx: Context = [
                "val": .string("outer"),
                "items": .list([["val": .string("inner")]]),
            ]
            let out = try render("{{#each items row}}", ctx).rawValue.runReader(env).get()
            #expect(out == "inner")
        }
    }
}

// MARK: - render: #if

@Suite("render — #if")
struct RenderIfTests {
    @Test func trueBoolShowsFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", ["flag": .bool(true)]).rawValue.runReader(env).get()
            #expect(out == "<p>shown</p>")
        }
    }

    @Test func falseBoolHidesFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", ["flag": .bool(false)]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func missingKeyHidesFragment() throws {
        try withFragmentDir(["yes": "<p>shown</p>"]) { env in
            let out = try render("{{#if flag yes}}", [:]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func nonEmptyStringIsTruthy() throws {
        try withFragmentDir(["yes": "X"]) { env in
            let out = try render("{{#if s yes}}", ["s": .string("hello")]).rawValue.runReader(env).get()
            #expect(out == "X")
        }
    }

    @Test func emptyStringIsFalsy() throws {
        try withFragmentDir(["yes": "X"]) { env in
            let out = try render("{{#if s yes}}", ["s": .string("")]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func nonEmptyListIsTruthy() throws {
        try withFragmentDir(["yes": "Y"]) { env in
            let ctx: Context = ["items": .list([["k": .string("v")]])]
            let out = try render("{{#if items yes}}", ctx).rawValue.runReader(env).get()
            #expect(out == "Y")
        }
    }

    @Test func emptyListIsFalsy() throws {
        try withFragmentDir(["yes": "Y"]) { env in
            let out = try render("{{#if items yes}}", ["items": .list([])]).rawValue.runReader(env).get()
            #expect(out.isEmpty)
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let result = render("{{#if flag missing}}", ["flag": .bool(true)]).rawValue.runReader(env)
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
            let out = try render("{{#include header}}", [:]).rawValue.runReader(env).get()
            #expect(out == "<h1>Title</h1>")
        }
    }

    @Test func fragmentReceivesContext() throws {
        try withFragmentDir(["greeting": "Hello {{name}}"]) { env in
            let out = try render("{{#include greeting}}", ["name": .string("World")]).rawValue.runReader(env).get()
            #expect(out == "Hello World")
        }
    }

    @Test func missingFragmentReturnsFailure() {
        let env = HTMLEnvironment.mockFailure(error: URLError(.fileDoesNotExist))
        let result = render("{{#include missing}}", [:]).rawValue.runReader(env)
        if case let .failure(e) = result, case let .readError(name, _) = e {
            #expect(name == "missing")
        } else {
            Issue.record("Expected .failure(.readError(\"missing\", _)), got \(result)")
        }
    }

    @Test func textBeforeAndAfterFragment() throws {
        try withFragmentDir(["nav": "<nav/>"]) { env in
            let out = try render("before{{#include nav}}after", [:]).rawValue.runReader(env).get()
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
            let out = try render("{{#include outer}}", ["val": .string("X")]).rawValue.runReader(env).get()
            #expect(out == "<outer><inner>X</inner></outer>")
        }
    }

    @Test func readerEnvironmentSelectsFragmentDirectory() throws {
        let a = try withFragmentDir(["g": "Hello"]) { env in
            try render("{{#include g}}", [:]).rawValue.runReader(env).get()
        }
        let b = try withFragmentDir(["g": "Goodbye"]) { env in
            try render("{{#include g}}", [:]).rawValue.runReader(env).get()
        }
        #expect(a == "Hello")
        #expect(b == "Goodbye")
    }

    @Test func eachInsideInclude() throws {
        try withFragmentDir([
            "list": "<ul>{{#each items row}}</ul>",
            "row": "<li>{{name}}</li>",
        ]) { env in
            let ctx: Context = ["items": .list([["name": .string("A")], ["name": .string("B")]])]
            let out = try render("{{#include list}}", ctx).rawValue.runReader(env).get()
            #expect(out == "<ul><li>A</li><li>B</li></ul>")
        }
    }

    @Test func errorInNestedFragmentPropagates() throws {
        try withFragmentDir(["outer": "{{#include inner}}"]) { env in
            let result = render("{{#include outer}}", [:]).rawValue.runReader(env)
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
        let env = HTMLEnvironment(find: { _ in nil }, readFile: { _ in .success("") })
        let result = loadTemplate("nonexistent").rawValue.runReader(env)
        guard case let .failure(e) = result, case .notFound = e else {
            Issue.record("Expected .failure(.notFound), got \(result)")
            return
        }
    }

    @Test func foundReturnsContents() {
        let result = loadTemplate("page").rawValue.runReader(.mockSuccess(contents: "<h1>Hi</h1>"))
        guard case let .success(html) = result else {
            Issue.record("Expected .success, got \(result)")
            return
        }
        #expect(html == "<h1>Hi</h1>")
    }

    @Test func readErrorPropagates() {
        let result = loadTemplate("page").rawValue.runReader(.mockFailure(error: URLError(.fileDoesNotExist)))
        guard case let .failure(e) = result, case .readError = e else {
            Issue.record("Expected .failure(.readError), got \(result)")
            return
        }
    }

    @Test func fragmentIsReadOncePerRender() throws {
        final class Reads: @unchecked Sendable { var names: [String] = [] }
        let reads = Reads()
        let files = ["row.template": "<li>{{name}}{{#include badge}}</li>", "badge.template": "*"]
        let env = HTMLEnvironment(
            find: { URL(fileURLWithPath: "/t/\($0)") },
            readFile: { url in
                reads.names.append(url.lastPathComponent)
                return files[url.lastPathComponent].map(Result.success) ?? .failure(URLError(.fileDoesNotExist))
            }
        )
        let ctx: Context = ["items": .list([["name": .string("a")], ["name": .string("b")], ["name": .string("c")]])]
        let out = try render("{{#each items row}}", ctx).rawValue.runReader(env).get()
        #expect(out == "<li>a*</li><li>b*</li><li>c*</li>")
        #expect(reads.names.sorted() == ["badge.template", "row.template"])
    }

    @Test func bindsIntoRender() throws {
        let page = loadTemplate("page") >>- { render($0, ["name": .string("World")]) }
        #expect(try page.rawValue.runReader(.mockSuccess(contents: "<p>{{name}}</p>")).get() == "<p>World</p>")
    }

    @Test func bindShortCircuitsOnLoadFailure() {
        let env = HTMLEnvironment(find: { _ in nil }, readFile: { _ in .success("") })
        let page = loadTemplate("missing") >>- { render($0, [:]) }
        guard case .failure(.notFound("missing")) = page.rawValue.runReader(env) else {
            Issue.record("Expected .failure(.notFound(\"missing\"))")
            return
        }
    }
}
