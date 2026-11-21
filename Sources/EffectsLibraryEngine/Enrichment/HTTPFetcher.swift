// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation

public struct FetchLimits: Sendable, Equatable {
    public var maxBytes: Int
    public var timeout: TimeInterval
    public var maxRedirects: Int
    /// Extra request headers (used only for the optional search service key; never set for page or image downloads).
    public var extraHeaders: [String: String]
    public init(maxBytes: Int, timeout: TimeInterval = 10, maxRedirects: Int = 3, extraHeaders: [String: String] = [:]) { self.maxBytes = maxBytes; self.timeout = timeout; self.maxRedirects = maxRedirects; self.extraHeaders = extraHeaders }
    public static let page = FetchLimits(maxBytes: 512 * 1024)
    public static let image = FetchLimits(maxBytes: 8 * 1024 * 1024, timeout: 15)
}

public struct FetchResult: Sendable { public let data: Data; public let finalURL: URL; public let contentType: String?
    public init(data: Data, finalURL: URL, contentType: String?) { self.data = data; self.finalURL = finalURL; self.contentType = contentType } }

public enum FetchError: Error, Equatable, CustomStringConvertible {
    case blocked(URLPolicy.Rejection), tooManyRedirects, tooLarge, timeout, offline, http(Int), cancelled, badResponse(String)
    public var description: String {
        switch self {
        case .blocked(let r): "Address not allowed: \(r)"
        case .tooManyRedirects: "Too many redirects."
        case .tooLarge: "The response is larger than the allowed limit."
        case .timeout: "The request timed out."
        case .offline: "No internet connection."
        case .http(let c): "The server answered with status \(c)."
        case .cancelled: "Cancelled."
        case .badResponse(let m): "Unexpected response: \(m)"
        }
    }
}

/// Network access seam: the real implementation talks to the Internet; tests inject a deterministic stub.
public protocol HTTPFetcher: Sendable {
    func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult
}

/// Streaming download to a file with progress (used only by the updater, after an explicit user action).
public protocol HTTPDownloader: Sendable {
    func download(_ url: URL, maxBytes: Int64, timeout: TimeInterval, to file: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws
}

/// Redirect bookkeeping, separated so it can be tested without a network.
public struct RedirectGuard: Sendable {
    public private(set) var hops = 0
    public let maxRedirects: Int
    public init(maxRedirects: Int) { self.maxRedirects = maxRedirects }
    public mutating func allow(_ next: URL) -> FetchError? {
        hops += 1
        if hops > maxRedirects { return .tooManyRedirects }
        if case .failure(let r) = URLPolicy.validate(next) { return .blocked(r) }
        return nil
    }
}

/// Real fetcher: https only, ephemeral session (no cookies, no cache, no credentials), generic User-Agent,
/// every redirect hop re-validated, DNS result checked, bounded size and time, streaming read that stops at the cap.
public final class URLSessionFetcher: NSObject, HTTPFetcher, HTTPDownloader, @unchecked Sendable {
    public static let userAgent = "ScanerGDC (+product-details lookup; contact via the project page)"
    private let resolveCheck: @Sendable (String) -> Bool
    public init(resolveCheck: @escaping @Sendable (String) -> Bool = { URLPolicy.resolvedAddressesAllowed(host: $0) }) { self.resolveCheck = resolveCheck }

    public func fetch(_ url: URL, limits: FetchLimits) async throws -> FetchResult {
        if case .failure(let r) = URLPolicy.validate(url) { throw FetchError.blocked(r) }
        guard let host = url.host, resolveCheck(host) else { throw FetchError.blocked(.privateAddress) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil; cfg.httpShouldSetCookies = false; cfg.urlCache = nil; cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = limits.timeout; cfg.timeoutIntervalForResource = limits.timeout * 2
        cfg.urlCredentialStorage = nil; cfg.waitsForConnectivity = false; cfg.httpAdditionalHeaders = ["User-Agent": Self.userAgent, "Accept-Language": "en"]
        let delegate = Delegate(maxRedirects: limits.maxRedirects, resolveCheck: resolveCheck)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var req = URLRequest(url: url); req.httpMethod = "GET"
        for (k, v) in limits.extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (bytes, resp) = try await session.bytes(for: req)
            if let e = delegate.error { throw e }
            guard let http = resp as? HTTPURLResponse, let final = http.url else { throw FetchError.badResponse("not HTTP") }
            if case .failure(let r) = URLPolicy.validate(final) { throw FetchError.blocked(r) }
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
            if http.expectedContentLength > Int64(limits.maxBytes) { throw FetchError.tooLarge }
            var data = Data(); data.reserveCapacity(min(limits.maxBytes, 64 * 1024))
            for try await b in bytes {
                data.append(b)
                if data.count > limits.maxBytes { throw FetchError.tooLarge }
                if Task.isCancelled { throw FetchError.cancelled }
            }
            return FetchResult(data: data, finalURL: final, contentType: http.value(forHTTPHeaderField: "Content-Type"))
        } catch let e as FetchError { throw e }
        catch let e as URLError {
            if let d = delegate.error { throw d }
            switch e.code {
            case .timedOut: throw FetchError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: throw FetchError.offline
            case .cancelled: throw delegate.error ?? FetchError.cancelled
            default: throw FetchError.badResponse(e.localizedDescription)
            }
        }
    }

    public func download(_ url: URL, maxBytes: Int64, timeout: TimeInterval, to file: URL, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        if case .failure(let r) = URLPolicy.validate(url) { throw FetchError.blocked(r) }
        guard let host = url.host, resolveCheck(host) else { throw FetchError.blocked(.privateAddress) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil; cfg.httpShouldSetCookies = false; cfg.urlCache = nil; cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = timeout; cfg.timeoutIntervalForResource = 600
        cfg.urlCredentialStorage = nil; cfg.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        let delegate = Delegate(maxRedirects: 5, resolveCheck: resolveCheck)
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let fm = FileManager.default
        fm.createFile(atPath: file.path, contents: nil)
        let out = try FileHandle(forWritingTo: file); defer { try? out.close() }
        do {
            let (bytes, resp) = try await session.bytes(for: URLRequest(url: url))
            if let e = delegate.error { throw e }
            guard let http = resp as? HTTPURLResponse, let final = http.url else { throw FetchError.badResponse("not HTTP") }
            if case .failure(let r) = URLPolicy.validate(final) { throw FetchError.blocked(r) }
            guard (200..<300).contains(http.statusCode) else { throw FetchError.http(http.statusCode) }
            let total: Int64? = http.expectedContentLength > 0 ? http.expectedContentLength : nil
            if let t = total, t > maxBytes { throw FetchError.tooLarge }
            var buf = Data(); buf.reserveCapacity(64 * 1024); var done: Int64 = 0; var lastReport: Int64 = 0
            for try await b in bytes {
                buf.append(b)
                if buf.count >= 64 * 1024 { try out.write(contentsOf: buf); done += Int64(buf.count); buf.removeAll(keepingCapacity: true)
                    if done > maxBytes { throw FetchError.tooLarge }
                    if done - lastReport >= 128 * 1024 { lastReport = done; progress(done, total) } }
                if Task.isCancelled { throw FetchError.cancelled }
            }
            if !buf.isEmpty { try out.write(contentsOf: buf); done += Int64(buf.count) }
            if done > maxBytes { throw FetchError.tooLarge }
            progress(done, total)
        } catch let e as FetchError { try? fm.removeItem(at: file); throw e }
        catch let e as URLError {
            try? fm.removeItem(at: file)
            if let d = delegate.error { throw d }
            switch e.code {
            case .timedOut: throw FetchError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: throw FetchError.offline
            case .cancelled: throw delegate.error ?? FetchError.cancelled
            default: throw FetchError.badResponse(e.localizedDescription)
            }
        } catch { try? fm.removeItem(at: file); throw error }
    }

    private final class Delegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private var guardRail: RedirectGuard
        private let resolveCheck: @Sendable (String) -> Bool
        private let lock = NSLock(); private var _error: FetchError?
        var error: FetchError? { lock.withLock { _error } }
        init(maxRedirects: Int, resolveCheck: @escaping @Sendable (String) -> Bool) { guardRail = RedirectGuard(maxRedirects: maxRedirects); self.resolveCheck = resolveCheck }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let next = request.url else { completionHandler(nil); return }
            var failure = lock.withLock { guardRail.allow(next) }
            if failure == nil, let h = next.host, !resolveCheck(h) { failure = .blocked(.privateAddress) }
            if let failure { lock.withLock { _error = failure }; completionHandler(nil); task.cancel(); return }
            completionHandler(request)
        }
    }
}
