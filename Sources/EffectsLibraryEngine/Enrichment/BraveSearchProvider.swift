// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

/// Optional discovery through the Brave Search API, with the USER'S OWN key (bring-your-own-key).
/// - No key is embedded in the app or its source; the key is read at call time from `keyProvider` (the app supplies the Keychain).
/// - Without a key this throws `SearchNotConfigured`: nothing is searched and nothing is sent.
/// - Only `LookupQuery` data (technical name, producer, kind) goes into the query text. Never paths, files, licenses or inventory.
/// - Results are used transiently to pick a candidate page; the service's terms forbid caching/storing results, so nothing from the
///   result list is persisted: the app stores only what it later reads from the producer's own page.
/// Request/response shape follows the provider's published Web Search reference (GET /res/v1/web/search, header X-Subscription-Token,
/// `web.results[].{title,url,description}`). Verified against stubs only; see docs/DISCOVERY.md for the live-verification status.
public struct BraveSearchProvider: SearchProvider {
    public static let endpoint = "https://api.search.brave.com/res/v1/web/search"
    private let fetcher: HTTPFetcher
    private let keyProvider: @Sendable () -> String?
    public init(fetcher: HTTPFetcher, keyProvider: @escaping @Sendable () -> String?) { self.fetcher = fetcher; self.keyProvider = keyProvider }

    static func queryText(_ q: LookupQuery) -> String {
        var parts = ["\"\(q.name.replacingOccurrences(of: "\"", with: ""))\""]
        if let p = q.producer, !p.isEmpty, p.lowercased() != "unknown" { parts.append(p) }
        parts.append(q.kind.lowercased().contains("lut") ? "LUT" : "plugin")
        return String(parts.joined(separator: " ").prefix(200))
    }

    public func search(_ q: LookupQuery) async throws -> [SearchCandidate] {
        guard let key = keyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { throw SearchNotConfigured() }
        var c = URLComponents(string: Self.endpoint)!
        c.queryItems = [URLQueryItem(name: "q", value: Self.queryText(q)), URLQueryItem(name: "count", value: "10"),
                        URLQueryItem(name: "safesearch", value: "strict"), URLQueryItem(name: "text_decorations", value: "false")]
        guard let url = c.url else { throw SearchFailure.badResponse("bad query") }
        let limits = FetchLimits(maxBytes: 512 * 1024, timeout: 10, maxRedirects: 0, extraHeaders: ["X-Subscription-Token": key, "Accept": "application/json"])
        let res: FetchResult
        do { res = try await fetcher.fetch(url, limits: limits) }
        catch FetchError.http(let code) where code == 401 || code == 403 { throw SearchFailure.unauthorized }
        catch FetchError.http(429) { throw SearchFailure.rateLimited }
        catch FetchError.http(let code) { throw SearchFailure.badResponse("status \(code)") }
        catch FetchError.offline, FetchError.timeout { throw SearchFailure.offline }
        catch FetchError.cancelled { throw CancellationError() }
        catch let e as FetchError { throw SearchFailure.badResponse(e.description) }
        return try Self.parse(res.data)
    }

    static func parse(_ data: Data) throws -> [SearchCandidate] {
        struct Reply: Decodable { struct W: Decodable { struct R: Decodable { let title: String?; let url: String? }; let results: [R]? }; let web: W? }
        guard let r = try? JSONDecoder().decode(Reply.self, from: data) else { throw SearchFailure.badResponse("not the expected JSON") }
        var seen = Set<String>(); var out: [SearchCandidate] = []
        for x in r.web?.results ?? [] {
            guard let t = x.title, let us = x.url, case .success(let u) = URLPolicy.parse(us), seen.insert(u.absoluteString).inserted else { continue }
            out.append(SearchCandidate(name: String(t.prefix(200)), producer: nil, pageURL: u))
        }
        return out
    }
}
