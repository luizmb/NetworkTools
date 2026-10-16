// SPDX-License-Identifier: Apache-2.0

import Foundation
import FP

// MARK: - Environment

public struct HTMLEnvironment: Sendable {
    /// Resolves a filename (including extension) to a URL, or `nil` if not found.
    public let find: @Sendable (String) -> URL?
    /// Reads the contents of a URL, returning an error on failure.
    public let readFile: @Sendable (URL) -> Result<String, Error>

    public init(
        find: @escaping @Sendable (String) -> URL?,
        readFile: @escaping @Sendable (URL) -> Result<String, Error>
    ) {
        self.find = find
        self.readFile = readFile
    }

    /// Direct filesystem: `find` appends the filename to `path`,
    /// `readFile` reads via `String(contentsOf:encoding:)`.
    public static func live(path: String) -> Self {
        let base = URL(fileURLWithPath: path)
        return Self(
            find: { filename in base.appendingPathComponent(filename) },
            readFile: { url in Result { try String(contentsOf: url, encoding: .utf8) } }
        )
    }

    #if !os(Linux)
    /// Bundle-based: `find` decomposes the filename into name + extension and calls
    /// `Bundle.url(forResource:withExtension:)`. `readFile` reads via `String(contentsOf:encoding:)`.
    public static func live(bundle: Bundle) -> Self {
        Self(
            find: { filename in
                bundle.url(forResource: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
                           withExtension: "template")
            },
            readFile: { url in Result { try String(contentsOf: url, encoding: .utf8) } }
        )
    }
    #endif

    /// Testing: `find` returns a synthetic URL, `readFile` always succeeds with `contents`.
    public static func mockSuccess(contents: String) -> Self {
        Self(
            find: { filename in URL(fileURLWithPath: "/mock/\(filename)") },
            readFile: { _ in .success(contents) }
        )
    }

    /// Testing: `find` returns a synthetic URL, `readFile` always fails with `error`.
    public static func mockFailure(error: Error) -> Self {
        Self(
            find: { filename in URL(fileURLWithPath: "/mock/\(filename)") },
            readFile: { _ in .failure(error) }
        )
    }
}

// MARK: - Context types

public typealias Context = [String: TemplateValue]

public indirect enum TemplateValue: Sendable {
    case string(String)
    case list([Context])
    case bool(Bool)
}

// MARK: - Errors

public enum TemplateError: Error {
    case notFound(String)
    case readError(String, Error)
}

// MARK: - Render

/// Renders `template`, resolving `{{key}}`, `{{#each key fragment}}`,
/// `{{#if key fragment}}` and `{{#include fragment}}` directives.
///
/// Returns the `ReaderTResult` stack, so it chains with `>>-` (`loadTemplate("index") >>- { render($0, ctx) }`);
/// leave with `.rawValue` to run it.
public func render(_ template: String, _ context: Context) -> ReaderTResult<HTMLEnvironment, TemplateError, String> {
    ReaderTResult(renderImpl(template, context))
}

// MARK: - Bundle-based loader

/// Resolves `name` via `env.findResource`, then reads its contents via `env.readFile`.
public func loadTemplate(_ name: String) -> ReaderTResult<HTMLEnvironment, TemplateError, String> {
    ReaderTResult(Reader { env in
        guard let url = env.find("\(name).template") else { return .failure(.notFound(name)) }
        return env.readFile(url).mapError { .readError(name, $0) }
    })
}

// MARK: - HTML escaping

/// Escapes `&`, `<` and `>`. Text with nothing to escape is returned as is, without a copy.
public func esc(_ s: String) -> String {
    escape(s, quotes: false)
}

/// ``esc(_:)`` plus `"`, for use inside an HTML attribute.
public func escAttr(_ s: String) -> String {
    escape(s, quotes: true)
}

// One pass over the UTF-8 bytes. The characters escaped are all ASCII, so the runs in between are
// appended whole, multi-byte characters included.
private func escape(_ s: String, quotes: Bool) -> String {
    let utf8 = s.utf8
    var output = ""
    var runStart = utf8.startIndex
    var index = utf8.startIndex
    while index != utf8.endIndex {
        let replacement: String? = switch utf8[index] {
        case UInt8(ascii: "&"): "&amp;"
        case UInt8(ascii: "<"): "&lt;"
        case UInt8(ascii: ">"): "&gt;"
        case UInt8(ascii: "\"") where quotes: "&quot;"
        default: nil
        }
        let next = utf8.index(after: index)
        if let replacement {
            if output.isEmpty { output.reserveCapacity(utf8.count + utf8.count / 8) }
            output += s[runStart ..< index]
            output += replacement
            runStart = next
        }
        index = next
    }
    guard runStart != utf8.startIndex else { return s }
    output += s[runStart...]
    return output
}

// MARK: - Private implementation

private func renderImpl(_ template: String, _ context: Context) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        var renderer = Renderer(env: env)
        var output = ""
        return renderer.render(template, context, into: &output).map { output }
    }
}

// Renders a whole template, nested `#each` / `#if` / `#include` fragments included, into one output
// buffer. Each fragment is read from the environment at most once per render, however many times
// it is used (an `#include` inside an `#each` fragment would otherwise be read once per item).
private struct Renderer {
    let env: HTMLEnvironment
    private var fragments: [String: Result<String, TemplateError>] = [:]

    init(env: HTMLEnvironment) {
        self.env = env
    }

    mutating func render(_ template: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        var remaining = template[...]

        while let openRange = find(UInt8(ascii: "{"), in: remaining) {
            output += remaining[..<openRange.lowerBound]
            remaining = remaining[openRange.upperBound...]

            guard let closeRange = find(UInt8(ascii: "}"), in: remaining) else {
                output += "{{"
                continue
            }

            let raw = remaining[..<closeRange.lowerBound]
            let token = raw.first?.isWhitespace == true || raw.last?.isWhitespace == true
                ? raw.trimmingCharacters(in: .whitespaces)
                : String(raw)
            remaining = remaining[closeRange.upperBound...]

            if case let .failure(error) = renderToken(token, context, into: &output) {
                return .failure(error)
            }
        }

        output += remaining
        return .success(())
    }

    private mutating func renderToken(_ token: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        if token.hasPrefix("#each ") {
            renderEach(token, context, into: &output)
        } else if token.hasPrefix("#if ") {
            renderIf(token, context, into: &output)
        } else if token.hasPrefix("#include ") {
            renderInclude(token, context, into: &output)
        } else {
            renderVariable(token, context, into: &output)
        }
    }

    private mutating func renderEach(_ token: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        let parts = words(token.dropFirst(6), limit: 2)
        guard parts.count == 2,
              case let .list(items) = context[parts[0]]
        else { return .success(()) }

        switch fragment(parts[1]) {
        case let .failure(error):
            return .failure(error)
        case let .success(frag):
            for item in items {
                if case let .failure(error) = render(frag, item, into: &output) { return .failure(error) }
            }
            return .success(())
        }
    }

    private mutating func renderIf(_ token: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        let parts = words(token.dropFirst(4), limit: 2)
        guard parts.count == 2, truthy(context[parts[0]]) else { return .success(()) }
        return renderFragment(parts[1], context, into: &output)
    }

    private mutating func renderInclude(_ token: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        renderFragment(token.dropFirst(9).trimmingCharacters(in: .whitespaces), context, into: &output)
    }

    private mutating func renderFragment(_ name: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        switch fragment(name) {
        case let .failure(error): .failure(error)
        case let .success(frag): render(frag, context, into: &output)
        }
    }

    private func renderVariable(_ token: String, _ context: Context, into output: inout String) -> Result<Void, TemplateError> {
        switch context[token] {
        case let .string(s): output += s
        case let .bool(b): output += b ? "true" : "false"
        case .list,
             nil: break
        }
        return .success(())
    }

    private mutating func fragment(_ name: String) -> Result<String, TemplateError> {
        if let cached = fragments[name] { return cached }
        let loaded = loadFragment(name).runReader(env)
        fragments[name] = loaded
        return loaded
    }
}

private func loadFragment(_ name: String) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        guard let url = env.find("\(name).template") else { return .failure(.notFound(name)) }
        return env.readFile(url).mapError { .readError(name, $0) }
    }
}

// The first `{{` (or `}}`) in `s`, found on its UTF-8 bytes. Both bytes are ASCII, so the range
// always falls on character boundaries.
private func find(_ byte: UInt8, in s: Substring) -> Range<Substring.Index>? {
    let utf8 = s.utf8
    var index = utf8.startIndex
    while let found = utf8[index...].firstIndex(of: byte) {
        let next = utf8.index(after: found)
        guard next != utf8.endIndex else { return nil }
        if utf8[next] == byte { return found ..< utf8.index(after: next) }
        index = next
    }
    return nil
}

private func truthy(_ value: TemplateValue?) -> Bool {
    switch value {
    case let .string(s): !s.isEmpty
    case let .bool(b): b
    case let .list(l): !l.isEmpty
    case nil: false
    }
}

private func words(_ s: Substring, limit: Int) -> [String] {
    s.split(separator: " ", maxSplits: limit - 1).map(String.init)
}
