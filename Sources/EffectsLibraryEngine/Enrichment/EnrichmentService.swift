// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import Foundation
import EffectsLibraryCore

/// The ONLY data a discovery service may receive about an item. There is deliberately no path, file content, license, serial,
/// user name or inventory field in this type.
public struct LookupQuery: Sendable, Equatable {
    public let name: String
    public let producer: String?
    public let bundleIdentifier: String?
    public let kind: String
    public init(item: EffectItem) { name = item.name; producer = item.vendor; bundleIdentifier = item.bundleIdentifier; kind = item.kind.title }
}

public struct SearchCandidate: Sendable, Equatable {
    public let name: String; public let producer: String?; public let pageURL: URL
    public init(name: String, producer: String?, pageURL: URL) { self.name = name; self.producer = producer; self.pageURL = pageURL }
}

/// Discovery adapter (finding a producer page from a name). No engine is bundled: it needs a search service, quota or credentials
/// that do not exist yet, and none is invented. `NoSearchProvider` says so honestly.
public protocol SearchProvider: Sendable {
    func search(_ q: LookupQuery) async throws -> [SearchCandidate]
}
public struct SearchNotConfigured: Error {}
/// Real failures of a configured discovery service (never used for "no results").
public enum SearchFailure: Error, Equatable, CustomStringConvertible {
    case offline, unauthorized, rateLimited, badResponse(String)
    public var description: String {
        switch self {
        case .offline: "No internet connection."
        case .unauthorized: "The search service rejected the key."
        case .rateLimited: "The search service limit was reached."
        case .badResponse(let m): "The search service answered unexpectedly (\(m))."
        }
    }
}
public struct NoSearchProvider: SearchProvider { public init() {}; public func search(_ q: LookupQuery) async throws -> [SearchCandidate] { throw SearchNotConfigured() } }

public enum LookupOutcome: Sendable, Equatable {
    case updated(ProductRecord)              // details read from a page the user associated
    case proposed(ProductRecord)             // needs the user's confirmation
    case searchUnavailable                   // no discovery service configured: NOTHING was searched
    /// Result of an automatic search. TRANSIENT: never written to disk (the search provider's terms do not allow storing results
    /// on a standard plan). The user can open a candidate and then associate a page manually; only that typed/pasted address is saved.
    case candidates([SearchCandidate], ambiguous: Bool)
    case notFound(String)                    // an effective search (or page read) produced nothing usable
    case skipped(String)                     // rejected by the user, or recent miss
    case failed(String, offline: Bool)
    case cancelled
}

public struct EnrichmentBatchSummary: Sendable, Equatable {
    public var requested = 0, completed = 0, proposed = 0, skipped = 0
    /// Distinct causes. `searchUnavailable` is NOT "not found": no search happened.
    public var searchUnavailable = 0, notFound = 0, candidatesFound = 0, ambiguous = 0, network = 0, errors = 0, manuallyAssociated = 0
    public var cancelled = false
    public var notes: [String] = []
    /// In-memory only (never persisted): candidate pages from an automatic search, keyed by item id.
    public var candidates: [String: [SearchCandidate]] = [:]
}

public actor EnrichmentService {
    private let store: EnrichmentStore
    private let fetcher: HTTPFetcher
    private let search: SearchProvider
    private let log: DiagnosticLog?
    private let now: @Sendable () -> Date

    public init(store: EnrichmentStore, fetcher: HTTPFetcher, search: SearchProvider = NoSearchProvider(), log: DiagnosticLog? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store; self.fetcher = fetcher; self.search = search; self.log = log; self.now = now
    }

    // MARK: single item

    /// "Search cover and details". `explicit` = the user asked for this very item (overrides a previous rejection / recent miss).
    public func lookup(_ item: EffectItem, explicit: Bool = true) async -> LookupOutcome {
        let key = ProductKey.make(for: item)
        let existing = await store.record(key)
        if !explicit {
            if existing?.status == .rejected { return .skipped("rejected earlier") }
            if await store.isRecentlyNotFound(key, now: now()) { return .skipped("not found recently") }
        }
        var page: URL?
        if let s = existing?.officialURL, let u = URL(string: s) { page = u }
        else {
            do {
                let candidates = try await search.search(LookupQuery(item: item))
                let scored = candidates.map { ($0, ProductMatcher.verdict(item: item, candidateName: $0.name, candidateProducer: $0.producer)) }
                    .filter { $0.1.confidence != .weak }.sorted { $0.1.score > $1.1.score }
                guard let top = scored.first else { await store.markNotFound(key, now: now()); return .notFound("No matching product page was found.") }
                let amb = top.1.confidence != .strong || (scored.count > 1 && scored[1].1.score >= top.1.score - 0.15)
                return .candidates(scored.prefix(3).map(\.0), ambiguous: amb)
            } catch is SearchNotConfigured { return .searchUnavailable }
            catch let e as SearchFailure { log?.warning("enrich", "enrich.search.failed", e.description); return .failed(e.description, offline: e == .offline) }
            catch { return .failed("The search service failed.", offline: false) }
        }
        guard let url = page else { return .searchUnavailable }
        return await readPage(item: item, key: key, url: url, existing: existing, automatic: false, carriedAmbiguity: nil)
    }

    /// "Associate official page": validates the address, stores it as the user's choice, then reads the details.
    public func associateOfficialPage(_ item: EffectItem, address: String) async -> LookupOutcome {
        switch URLPolicy.parse(address) {
        case .failure(let r): return .failed(r.description, offline: false)
        case .success(let u):
            let key = ProductKey.make(for: item)
            let rec = await store.setOfficialURL(key: key, url: u)
            return await readPage(item: item, key: key, url: u, existing: rec, automatic: false, carriedAmbiguity: nil)
        }
    }

    private func readPage(item: EffectItem, key: String, url: URL, existing: ProductRecord?, automatic: Bool, carriedAmbiguity: String?) async -> LookupOutcome {
        log?.info("enrich", "enrich.fetch.page", "host=\(url.host ?? "?")")
        let res: FetchResult
        do { res = try await fetcher.fetch(url, limits: .page) }
        catch FetchError.cancelled { return .cancelled }
        catch FetchError.offline { return .failed("No internet connection.", offline: true) }
        catch FetchError.timeout { return .failed("The request timed out.", offline: true) }
        catch let e as FetchError { log?.warning("enrich", "enrich.fetch.failed", e.description); return .failed(e.description, offline: false) }
        catch { return .failed("Network error.", offline: false) }
        if let ct = res.contentType?.lowercased(), !(ct.contains("html") || ct.contains("xml")) { return .failed("The address is not a web page.", offline: false) }
        let meta = PageMetadataExtractor.extract(html: res.data, baseURL: res.finalURL)
        let verdict = ProductMatcher.verdict(item: item, candidateName: meta.title, candidateProducer: meta.siteName)
        var r = existing ?? ProductRecord(key: key)
        let userURL = r.userChoseURL
        r.productName = meta.title ?? r.productName; r.producer = meta.siteName ?? r.producer; r.summary = meta.description ?? r.summary
        r.officialURL = r.officialURL ?? (meta.canonicalURL ?? res.finalURL).absoluteString
        r.sourceURL = res.finalURL.absoluteString; r.retrievedAt = now()
        if !r.userChoseImage, r.cover == nil || r.cover?.origin == .officialPage { r.proposedImageURL = meta.imageURL?.absoluteString }
        let mustConfirm = automatic || (!userURL && verdict.confidence != .strong)
        r.status = mustConfirm ? .proposed : .confirmed
        r.ambiguity = mustConfirm ? (carriedAmbiguity ?? verdict.note ?? "Found automatically: please confirm.") : (verdict.confidence == .strong ? nil : verdict.note)
        if meta.title == nil && meta.description == nil && meta.imageURL == nil { return .notFound("The page has no readable product details.") }
        await store.upsert(r)
        return mustConfirm ? .proposed(r) : .updated(r)
    }

    // MARK: image

    /// Downloads and stores the proposed page image after the user accepts it. Never replaces a user-chosen image unless told to.
    public func acceptProposedImage(key: String, replaceUserImage: Bool = false) async -> Result<ProductRecord, FetchOrImageError> {
        guard let r = await store.record(key), let s = r.proposedImageURL, let url = URL(string: s) else { return .failure(.nothingProposed) }
        if r.userChoseImage && !replaceUserImage { return .failure(.userImageKept) }
        do {
            let res = try await fetcher.fetch(url, limits: .image)
            switch ImageSanitizer.sanitize(res.data) {
            case .failure(let f): return .failure(.image(f))
            case .success(let clean):
                let saved = try await store.setFetchedCover(key: key, clean: clean, sourceURL: res.finalURL)
                return .success(saved)
            }
        } catch let e as FetchError { return .failure(.fetch(e)) }
        catch { return .failure(.fetch(.badResponse(error.localizedDescription))) }
    }

    public func setLocalImage(_ item: EffectItem, data: Data) async -> Result<ProductRecord, FetchOrImageError> {
        switch ImageSanitizer.sanitize(data) {
        case .failure(let f): return .failure(.image(f))
        case .success(let clean):
            do { return .success(try await store.setUserImage(key: ProductKey.make(for: item), clean: clean)) }
            catch { return .failure(.fetch(.badResponse("could not save the image"))) }
        }
    }

    // MARK: batch

    /// "Fill items without cover" for an explicit selection. Items the user already decided on are not touched.
    public func fill(_ items: [EffectItem], concurrency: Int = 2, progress: @Sendable @escaping (Int, Int) -> Void = { _, _ in }) async -> EnrichmentBatchSummary {
        var s = EnrichmentBatchSummary(); s.requested = items.count
        var done = 0
        await withTaskGroup(of: (EffectItem, LookupOutcome)?.self) { g in
            var next = 0
            func launch() { guard next < items.count else { return }; let it = items[next]; next += 1
                g.addTask { if Task.isCancelled { return nil }
                    let rec = await self.store.record(ProductKey.make(for: it))
                    if rec?.userChoseImage == true { return (it, .skipped("manual image")) }
                    return (it, await self.lookup(it, explicit: false)) } }
            for _ in 0..<min(concurrency, items.count) { launch() }
            while let pair = await g.next() {
                done += 1; progress(done, items.count)
                let r = pair?.1
                switch r {
                case nil, .cancelled?: s.cancelled = true
                case .updated(let r)?: if r.userChoseURL { s.manuallyAssociated += 1 } else { s.completed += 1 }
                case .proposed?: s.proposed += 1
                case .candidates(let c, let amb)?: s.candidatesFound += 1; if amb { s.ambiguous += 1 }; if let it = pair?.0 { s.candidates[it.id] = c }
                case .searchUnavailable?: s.searchUnavailable += 1
                case .notFound?: s.notFound += 1
                case .skipped?: s.skipped += 1
                case .failed(_, let off)?: if off { s.network += 1 } else { s.errors += 1 }
                }
                if Task.isCancelled { s.cancelled = true } else { launch() }
            }
        }
        log?.info("enrich", s.cancelled ? "enrich.batch.cancelled" : "enrich.batch.done",
                  "requested=\(s.requested) completed=\(s.completed) proposed=\(s.proposed) searchUnavailable=\(s.searchUnavailable) notFound=\(s.notFound) candidates=\(s.candidatesFound) ambiguous=\(s.ambiguous) manual=\(s.manuallyAssociated) network=\(s.network) errors=\(s.errors)")
        return s
    }
}

public enum FetchOrImageError: Error, Equatable, CustomStringConvertible {
    case nothingProposed, userImageKept, fetch(FetchError), image(ImageSanitizer.Failure)
    public var description: String {
        switch self {
        case .nothingProposed: "There is no proposed image."
        case .userImageKept: "Your own image is kept."
        case .fetch(let e): e.description
        case .image(let f): f.description
        }
    }
}
