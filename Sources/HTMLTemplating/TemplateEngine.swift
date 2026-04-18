import Foundation
import FP

// MARK: - Environment

public struct HTMLEnvironment {
    /// Resolves a filename (including extension) to a URL, or `nil` if not found.
    public let find: (String) -> URL?
    /// Reads the contents of a URL, returning an error on failure.
    public let readFile: (URL) -> Result<String, Error>

    public init(
        find: @escaping (String) -> URL?,
        readFile: @escaping (URL) -> Result<String, Error>
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

public indirect enum TemplateValue {
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
public func render(_ template: String, _ context: Context) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    renderImpl(template, context)
}

// MARK: - Bundle-based loader

/// Resolves `name` via `env.findResource`, then reads its contents via `env.readFile`.
public func loadTemplate(_ name: String) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        guard let url = env.find("\(name).template") else { return .failure(.notFound(name)) }
        return env.readFile(url).mapError { .readError(name, $0) }
    }
}

// MARK: - HTML escaping

public func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}

public func escAttr(_ s: String) -> String {
    esc(s).replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Private implementation

private func loadFragment(_ name: String) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        guard let url = env.find("\(name).template") else { return .failure(.notFound(name)) }
        return env.readFile(url).mapError { .readError(name, $0) }
    }
}

private func renderImpl(_ template: String, _ context: Context) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        var output    = ""
        var remaining = template[...]

        while let openRange = remaining.range(of: "{{") {
            output    += remaining[..<openRange.lowerBound]
            remaining  = remaining[openRange.upperBound...]

            guard let closeRange = remaining.range(of: "}}") else {
                output += "{{"
                continue
            }

            let token = String(remaining[..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            remaining = remaining[closeRange.upperBound...]

            if token.hasPrefix("#each ") {
                let parts = words(token.dropFirst(6), limit: 2)
                guard parts.count == 2,
                      case .list(let items) = context[parts[0]]
                else { continue }

                switch loadFragment(parts[1])
                    .runReader(env)
                    .flatMap({ frag in
                        items.reduce(.success("")) { acc, item in
                            acc.flatMap { prev in
                                renderImpl(frag, item).runReader(env).map { prev + $0 }
                            }
                        }
                    }) {
                case .success(let s): output += s
                case .failure(let e): return .failure(e)
                }

            } else if token.hasPrefix("#if ") {
                let parts = words(token.dropFirst(4), limit: 2)
                guard parts.count == 2, truthy(context[parts[0]]) else { continue }

                switch loadFragment(parts[1])
                    .runReader(env)
                    .flatMap({ frag in renderImpl(frag, context).runReader(env) }) {
                case .success(let s): output += s
                case .failure(let e): return .failure(e)
                }

            } else if token.hasPrefix("#include ") {
                let name = String(token.dropFirst(9)).trimmingCharacters(in: .whitespaces)

                switch loadFragment(name)
                    .runReader(env)
                    .flatMap({ frag in renderImpl(frag, context).runReader(env) }) {
                case .success(let s): output += s
                case .failure(let e): return .failure(e)
                }

            } else {
                switch context[token] {
                case .string(let s): output += s
                case .bool(let b):   output += b ? "true" : "false"
                case .list, nil:     break
                }
            }
        }

        output += remaining
        return .success(output)
    }
}

private func truthy(_ value: TemplateValue?) -> Bool {
    switch value {
    case .string(let s): !s.isEmpty
    case .bool(let b):   b
    case .list(let l):   !l.isEmpty
    case nil:            false
    }
}

private func words(_ s: Substring, limit: Int) -> [String] {
    s.split(separator: " ", maxSplits: limit - 1).map(String.init)
}
