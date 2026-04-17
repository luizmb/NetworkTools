import Foundation
import FP

// MARK: - Environment

public struct HTMLEnvironment {
    public let fragmentsDir: String
    public let findResource: (String) -> URL?
    public let readFile: (String) -> Result<String, Error>

    public init(
        fragmentsDir: String,
        findResource: @escaping (String) -> URL?,
        readFile: @escaping (String) -> Result<String, Error>
    ) {
        self.fragmentsDir = fragmentsDir
        self.findResource = findResource
        self.readFile = readFile
    }

    public static func live(path: String, bundle: Bundle = .main) -> Self {
        Self(
            fragmentsDir: path,
            findResource: { name in
                bundle.url(forResource: name, withExtension: "html",
                           subdirectory: "Resources/templates")
            },
            readFile: { filePath in
                Result { try String(contentsOfFile: filePath, encoding: .utf8) }
            }
        )
    }

    public static func mockSuccess(contents: String) -> Self {
        Self(
            fragmentsDir: "",
            findResource: { name in URL(fileURLWithPath: "/mock/\(name).html") },
            readFile: { _ in .success(contents) }
        )
    }

    public static func mockFailure(error: Error) -> Self {
        Self(
            fragmentsDir: "",
            findResource: { name in URL(fileURLWithPath: "/mock/\(name).html") },
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
/// Fragment files are loaded as `<env.fragmentsDir>/<name>.html.template`.
public func render(_ template: String, _ context: Context) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in renderImpl(template, context, env: env) }
}

// MARK: - Bundle-based loader

/// Loads a template source from the bundle via `env.findResource`, then reads
/// it via `env.readFile`. Both operations are injectable through `HTMLEnvironment`.
public func loadTemplate(_ name: String) -> Reader<HTMLEnvironment, Result<String, TemplateError>> {
    Reader { env in
        guard let url = env.findResource(name) else {
            return .failure(.notFound(name))
        }
        return env.readFile(url.path).mapError { .readError(name, $0) }
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

private func loadFragment(_ name: String, env: HTMLEnvironment) -> Result<String, TemplateError> {
    let path = "\(env.fragmentsDir)/\(name).html.template"
    return env.readFile(path).mapError { .readError(name, $0) }
}

private func renderImpl(_ template: String, _ context: Context, env: HTMLEnvironment) -> Result<String, TemplateError> {
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

            switch loadFragment(parts[1], env: env)
                .flatMap({ frag in
                    items.reduce(.success("")) { acc, item in
                        acc.flatMap { prev in
                            renderImpl(frag, item, env: env).map { prev + $0 }
                        }
                    }
                }) {
            case .success(let s): output += s
            case .failure(let e): return .failure(e)
            }

        } else if token.hasPrefix("#if ") {
            let parts = words(token.dropFirst(4), limit: 2)
            guard parts.count == 2, truthy(context[parts[0]]) else { continue }

            switch loadFragment(parts[1], env: env)
                .flatMap({ frag in renderImpl(frag, context, env: env) }) {
            case .success(let s): output += s
            case .failure(let e): return .failure(e)
            }

        } else if token.hasPrefix("#include ") {
            let name = String(token.dropFirst(9)).trimmingCharacters(in: .whitespaces)

            switch loadFragment(name, env: env)
                .flatMap({ frag in renderImpl(frag, context, env: env) }) {
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
