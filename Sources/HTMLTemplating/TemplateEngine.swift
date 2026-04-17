import Foundation
import FP

// MARK: - Environment

public struct HTMLEnvironment {
    public let loadFragment: (String) -> Result<String, TemplateError>

    public init(loadFragment: @escaping (String) -> Result<String, TemplateError>) {
        self.loadFragment = loadFragment
    }

    public init(fragmentsDir: String) {
        self.init { name in
            let path = "\(fragmentsDir)/\(name).html.template"
            return Result { try String(contentsOfFile: path, encoding: .utf8) }
                .mapError { .readError(name, $0) }
        }
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

// MARK: - HTML escaping

public func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}

public func escAttr(_ s: String) -> String {
    esc(s).replacingOccurrences(of: "\"", with: "&quot;")
}

// MARK: - Bundle-based loader

public func loadTemplate(_ name: String, in bundle: Bundle) -> Result<String, TemplateError> {
    guard let url = bundle.url(forResource: name, withExtension: "html",
                               subdirectory: "Resources/templates") else {
        return .failure(.notFound(name))
    }
    return Result { try String(contentsOf: url, encoding: .utf8) }
        .mapError { .readError(name, $0) }
}

// MARK: - Private implementation

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

            switch env.loadFragment(parts[1])
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

            switch env.loadFragment(parts[1])
                .flatMap({ frag in renderImpl(frag, context, env: env) }) {
            case .success(let s): output += s
            case .failure(let e): return .failure(e)
            }

        } else if token.hasPrefix("#include ") {
            let name = String(token.dropFirst(9)).trimmingCharacters(in: .whitespaces)

            switch env.loadFragment(name)
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
