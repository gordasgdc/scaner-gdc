# Automatic product discovery — service comparison and status

Need: find a producer's page from a technical name + producer, for a free open-source desktop app, with no backend, no embedded key,
no scraping of search pages. Researched 2026-11-21 from the services' own documentation/terms.

| Service | Desktop app, no backend | Key | Cost / limits | Results & images terms | Verdict |
|---|---|---|---|---|---|
| Brave Search API | yes (HTTPS GET, header `X-Subscription-Token`) | **required** (user's own) | official pricing page: $5.00 per 1,000 requests, "$5 free credits every month", 50 req/s; the earlier free plan was reportedly retired | Terms (updated 1 Sep 2026): no storing/caching/database of results beyond transient storage; no redistribution; key not shareable; attribution optional ("POWERED BY BRAVE"); no implying endorsement | **Recommended** as bring-your-own-key |
| Bing Search API | – | – | retired 11 Aug 2025 | – | unavailable |
| Google Custom Search JSON API | yes | key + engine id | closed to new customers; shutdown 1 Jan 2027 | – | unsuitable |
| Wikidata / Wikimedia APIs | yes | none (User-Agent mandatory) | rate limits | open data, but a live probe found essentially no coverage of plugin names | works, useless for this need |
| DuckDuckGo | no official search API found | – | – | scraping the HTML page is fragile and against the spirit of its terms | rejected |
| SerpApi, Tavily, Exa, Bright Data | yes | paid key | paid | resale/scraping intermediaries | rejected (cost, intermediary) |

Investigated: the services above. None of those found offered keyless, terms-compliant name-to-page discovery for plugin names; this does not prove that no such variant exists. What this version offers: manual association (always), optional own-key Brave search with transient results.

## Recommendation
**Brave Search API, bring-your-own-key.** Each user creates their own account/key (the owner of this project creates nothing and holds no key, so
there is no shared quota, no backend and nothing to leak). The key lives only in the user's Keychain. Pricing and terms bind that user, not the project.
Decision (owner, 2026-11-21): keep it as an advanced, experimental, off-by-default option; the app is fully usable without it.

## Terms and persistence (decision)
Brave's Search API Terms of Use (updated 1 Sep 2026, https://api-dashboard.search.brave.com/terms-of-service) forbid storing, caching or building a database of Search Results beyond
transient storage needed to operate the application, and forbid derivative works of results; its product page (https://brave.com/search/api/) states that storing results requires a
custom plan ("search with storage rights"). A user's standard plan therefore does not clearly permit retention, and the user's click in the app is not contractual permission.
**Consequence implemented:** results are never persisted. They are held in memory for the session; the user may open a candidate and associate a page by pasting its address
(the user's own act); only that address and what the app then reads from the producer's page are saved. No attribution is displayed (none is stored/derived; attribution is optional under the terms). A user with a storage-rights plan would need a separate, explicit opt-in flow; none is implemented.

## Verification status (be explicit)
- Verified live from the built tooling: HTTPS page read, official page read, image download+decode, redirects (2 followed, 6 refused), timeout, cancel,
  blocked http/localhost — see `net-probe-0.5.0.log` in the evidence folder.
- Verified live: the Brave endpoint is reachable and answers a structured error when no key is sent (HTTP 422, missing `x-subscription-token`).
- **NOT verified:** a real authenticated search. That needs a key from an account the owner/user must create; none was created. The parser and request
  shape follow Brave's published reference (`web.results[].{title,url}`) and are tested with stubbed responses only.
- The batch/UI states are tested deterministically. The feature is documented as "optional, own key, not verified live", not as available.
