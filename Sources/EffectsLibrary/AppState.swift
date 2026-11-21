// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import AppKit
import EffectsLibraryCore
import EffectsLibraryEngine

enum SidebarSelection: Hashable {
    case all, duplicates, disabled, activity
    case kind(ItemKind)
    case source(String)
}

/// A management action waiting for the user's in-app confirmation.
struct PendingOperation: Identifiable { let id = UUID(); var plan: OperationPlan; var item: EffectItem }

@MainActor
@Observable
final class AppState {
    // Data
    var items: [EffectItem] = []
    var sources: [LibrarySource] = []
    var origin: InventoryOrigin = .live
    var lastScanDate: Date?
    private(set) var isScanning = false
    var scanProgress: ScanProgress?
    var lastScanNote: String?

    // Query / selection
    var query = LibraryQuery()
    var sidebar: SidebarSelection = .all { didSet { applySidebar() } }
    var selectedItemID: String?

    // Layout / preferences
    var inspectorVisible = true
    var showPreviews = true
    var appearance: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    var textSize: TextSize = TextSize(rawValue: UserDefaults.standard.string(forKey: "textSize") ?? "") ?? .normal {
        didSet { UserDefaults.standard.set(textSize.rawValue, forKey: "textSize") }
    }

    // Previews
    var previews: [String: PreviewState] = [:]
    var originalReference: NSImage?
    var cacheLimitMB: Int = 64 { didSet { UserDefaults.standard.set(cacheLimitMB, forKey: "cacheLimitMB") } }
    var regenerating = false

    // Product details (optional online enrichment: OFF until the user turns it on)
    var onlineLookupEnabled = UserDefaults.standard.bool(forKey: "onlineLookupEnabled") { didSet { UserDefaults.standard.set(onlineLookupEnabled, forKey: "onlineLookupEnabled") } }
    var products: [String: ProductRecord] = [:]
    var coverImages: [String: NSImage] = [:]
    var enrichProgress: (done: Int, total: Int)?
    var enrichSummary: EnrichmentBatchSummary?
    /// True when the user stored their own search key. Automatic discovery exists only then.
    var searchKeyPresent = false
    /// Search results are kept in memory only for this session (the provider's terms do not allow storing them).
    var transientCandidates: [String: [SearchCandidate]] = [:]
    var pendingConsent: ConsentRequest?
    var pendingAssociate: EffectItem?
    var pendingBatch: [EffectItem]?
    var productMessage: String?
    let enrichmentStore: EnrichmentStore
    let enrichment: EnrichmentService
    var enrichTask: Task<Void, Never>?

    // Management
    var pending: PendingOperation?
    var operationMessage: String?
    var journalEntries: [JournalEntry] = []
    var recoveryNotes: [String] = []
    var disabledRootOverride: String?
    var debugLogging = false

    // Engine
    let storage: StorageLocations
    let log: DiagnosticLog
    let journal: OperationJournal
    private let previewService: PreviewService
    private let management: ManagementEngine
    private let scanner: LibraryScanner
    private var sourcesFile: SourcesFile
    private var scanTask: Task<Void, Never>?
    private var didApplyDevSidebar = false
    private let appInfo: AppInfo
    let standardSources: [SourceDescriptor]

    enum PreviewState { case loading, image(NSImage, isRender: Bool), unavailable(String) }

    init(mock: Bool = CommandLine.arguments.contains("--mock") || ProcessInfo.processInfo.environment["GEL_MOCK"] == "1") {
        let st = StorageLocations.fromEnvironment()
        try? st.createDirectories()
        storage = st
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        appInfo = AppInfo(version: v, build: b)
        log = DiagnosticLog(fileURL: st.logFile, appInfo: appInfo)
        journal = OperationJournal(url: st.journalFile)
        scanner = LibraryScanner(log: log)
        previewService = PreviewService(cache: PreviewCache(directory: st.previewCacheDir, maxBytes: UserDefaults.standard.integer(forKey: "cacheLimitMB").nonZero(64) * 1_048_576), log: log)
        enrichmentStore = EnrichmentStore(locations: st)
        let netFetcher = URLSessionFetcher()
        enrichment = EnrichmentService(store: enrichmentStore, fetcher: netFetcher, search: BraveSearchProvider(fetcher: netFetcher, keyProvider: { SearchKeyStore.read() }), log: log)
        searchKeyPresent = SearchKeyStore.read() != nil
        management = ManagementEngine(journal: journal, log: log, hosts: RunningAppsProbe())
        let sf = (try? JSONStore<SourcesFile>(url: st.sourcesFile).loadValidated()) ?? SourcesFile()
        sourcesFile = sf
        standardSources = ProcessInfo.processInfo.environment["GEL_NO_STANDARD"] == "1" ? [] : StandardSources.all()
        disabledRootOverride = sf.disabledRootOverride
        cacheLimitMB = UserDefaults.standard.integer(forKey: "cacheLimitMB").nonZero(64)
        log.info("app", "app.start", "mode=\(mock ? "mock" : "live")")
        if mock {
            items = MockData.items; sources = MockData.sources; origin = .mock
        } else {
            if let snap = try? JSONStore<InventorySnapshot>(url: st.inventoryFile).loadValidated() {
                items = snap.items; sources = snap.sources; origin = .lastKnown; lastScanDate = snap.savedAt
            }
            Task { await self.recoverAndScan() }
        }
        refreshJournal()
        Task { await self.loadProducts() }
    }

    // MARK: Derived
    var visibleItems: [EffectItem] { query.apply(to: items) }
    var duplicateKeys: Set<String> { LibraryQuery.duplicateKeys(in: items) }
    var vendors: [String] { LibraryQuery.vendors(in: items) }
    var hasUnknownVendor: Bool { items.contains { $0.vendor == nil } }
    var selectedItem: EffectItem? { items.first { $0.id == selectedItemID } }
    var disabledCount: Int { items.filter { $0.state == .disabled }.count }
    var activeItems: [EffectItem] { items.filter { $0.state == .active } }

    var dataOriginNote: String {
        switch origin {
        case .mock: "Sample data (mock). Not your real library."
        case .live: lastScanDate.map { "Live scan · \($0.formatted(date: .omitted, time: .shortened))" } ?? "Live"
        case .lastKnown: "Last known inventory\(lastScanDate.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""). Rescan to refresh."
        }
    }

    func source(for item: EffectItem) -> LibrarySource? { sources.first { $0.id == item.sourceID } }
    func count(for kind: ItemKind) -> Int { items.filter { $0.kind == kind && $0.state == .active }.count }
    func count(forSource id: String) -> Int { items.filter { $0.sourceID == id }.count }
    func isDuplicate(_ item: EffectItem) -> Bool { item.state == .active && duplicateKeys.contains(item.duplicateKey) }
    func otherLocations(of item: EffectItem) -> [EffectItem] { items.filter { $0.duplicateKey == item.duplicateKey && $0.id != item.id && $0.state == .active } }

    private func applySidebar() {
        query.kinds = []; query.sourceID = nil; query.onlyDuplicates = false; query.state = .active
        switch sidebar {
        case .all, .activity: break
        case .duplicates: query.onlyDuplicates = true
        case .disabled: query.state = .disabled
        case .kind(let k): query.kinds = [k]
        case .source(let id): query.sourceID = id; query.state = nil
        }
        dropSelectionIfHidden()
    }
    func dropSelectionIfHidden() { selectedItemID = SelectionNavigation.reconcile(current: selectedItemID, visible: visibleItems.map(\.id)) }
    func moveSelection(by delta: Int) { selectedItemID = SelectionNavigation.move(current: selectedItemID, in: visibleItems.map(\.id), by: delta) }

    // MARK: Scanning
    private func allDescriptors() -> [SourceDescriptor] {
        InventoryAssembler.descriptors(standard: standardSources, custom: sourcesFile.custom,
                                       disabledOverride: disabledRootOverride.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    func recoverAndScan() async {
        let reports = await management.recoverInterrupted()
        recoveryNotes = reports.map { "\($0.itemName): \($0.action)" }
        refreshJournal()
        startScan()
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true; scanProgress = nil; lastScanNote = nil
        let descs = allDescriptors()
        scanTask = Task { [weak self] in
            guard let self else { return }
            var summary: ScanSummary?
            for await ev in scanner.scan(descs) {
                switch ev {
                case .progress(let p): scanProgress = p
                case .finished(let s): summary = s
                case .sourceFinished: break
                }
            }
            finishScan(summary)
        }
    }

    func cancelScan() { scanTask?.cancel(); log.info("scan", "scan.cancel.requested") }

    private func finishScan(_ summary: ScanSummary?) {
        isScanning = false; scanProgress = nil
        guard let summary else { return }
        if summary.cancelled {
            lastScanNote = "Scan cancelled; showing the previous inventory."
            return
        }
        let inv = InventoryAssembler.assemble(summary.results, journal: journal)
        // A source that failed to read keeps its last-known items instead of silently becoming empty.
        var keptItems = inv.items
        var keptSources = inv.sources
        for s in inv.sources where { if case .unavailable = s.availability { return true } else { return false } }() {
            let old = items.filter { $0.sourceID == s.id }
            keptItems += old
            if let i = keptSources.firstIndex(where: { $0.id == s.id }) { keptSources[i].warnings.append("Showing last known items; this source could not be read.") }
        }
        items = keptItems; sources = keptSources; origin = .live; lastScanDate = Date()
        let failed = keptSources.filter { if case .unavailable = $0.availability { return true } else { return false } }.count
        lastScanNote = failed > 0 ? "\(failed) source(s) could not be read; their last known items are kept." : nil
        try? JSONStore<InventorySnapshot>(url: storage.inventoryFile).save(InventorySnapshot(sources: keptSources, items: keptItems))
        dropSelectionIfHidden()
        if let side = ProcessInfo.processInfo.environment["GEL_SIDEBAR"], !didApplyDevSidebar {
            didApplyDevSidebar = true
            sidebar = side == "disabled" ? .disabled : side == "activity" ? .activity : .all   // verification hook
        }
        if let name = ProcessInfo.processInfo.environment["GEL_SELECT"]?.replacingOccurrences(of: "_", with: " "), selectedItemID == nil, let it = keptItems.first(where: { $0.name == name }) {
            selectedItemID = it.id   // dev/verification hook
            switch ProcessInfo.processInfo.environment["GEL_PENDING"] {   // verification hooks (no effect without the variable)
            case "disable": requestDisable(it)
            case "consent": pendingConsent = ConsentRequest(proceed: {})
            case "associate": pendingAssociate = it
            case "batch": pendingBatch = keptItems.filter { $0.previewSupport == .none }.prefix(6).map { $0 }
            default: break
            }
        }
        previews = previews.filter { p in keptItems.contains { $0.id == p.key } }
    }

    // MARK: Custom sources
    func addCustomSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Add Source"; panel.message = "Choose a folder to scan (read-only). It is searched for OFX, LUT, DCTL, VST3, Audio Unit and VST items."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rec = CustomSourceRecord(path: url.path, kinds: Set(ItemKind.allCases), bookmark: try? url.bookmarkData(options: .withSecurityScope), displayName: url.lastPathComponent)
        guard !sourcesFile.custom.contains(where: { $0.id == rec.id }) else { return }
        sourcesFile.custom.append(rec); saveSources(); startScan()
    }

    func removeCustomSource(_ id: String) {
        sourcesFile.custom.removeAll { $0.id == id }; saveSources()
        items.removeAll { $0.sourceID == id || $0.sourceID == id + ".disabled" }; sources.removeAll { $0.id == id || $0.id == id + ".disabled" }
        if case .source(let s) = sidebar, s == id { sidebar = .all }
        startScan()
    }
    func isCustom(_ id: String) -> Bool { sourcesFile.custom.contains { $0.id == id } }

    func setDisabledRoot(_ url: URL?) {
        disabledRootOverride = url?.path; sourcesFile.disabledRootOverride = url?.path; saveSources(); startScan()
    }
    private func saveSources() {
        do { try JSONStore<SourcesFile>(url: storage.sourcesFile).save(sourcesFile) }
        catch { log.error("persistence", "sources.save.failed", "\(error)") }
    }

    // MARK: Finder / clipboard
    func copyPath(_ item: EffectItem) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
    func reveal(_ item: EffectItem) {
        if FileManager.default.fileExists(atPath: item.path) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
        else { operationMessage = "\(item.name) is no longer at \(item.path). Rescan to refresh."; log.warning("ui", "reveal.missing") }
    }
    func revealSourceFolders() {
        let urls = sources.filter { $0.availability == .available && $0.parentSourceID == nil }.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: Previews
    func loadPreview(_ item: EffectItem, regenerate: Bool = false) {
        if !regenerate, case .image = previews[item.id] ?? .loading { return }
        if !regenerate, case .unavailable = previews[item.id] ?? .loading { return }
        previews[item.id] = .loading
        Task {
            let r = await previewService.preview(for: item, regenerate: regenerate)
            switch r {
            case .image(let png, _, let isRender): previews[item.id] = NSImage(data: png).map { .image($0, isRender: isRender) } ?? .unavailable("The preview image could not be decoded.")
            case .unavailable(let reason): previews[item.id] = .unavailable(reason)
            }
            if originalReference == nil, let d = await previewService.originalPNG() { originalReference = NSImage(data: d) }
        }
    }
    func regenerateAllVisible() {
        guard !regenerating else { return }
        regenerating = true
        let list = visibleItems
        Task {
            _ = await previewService.regenerate(list, concurrency: 3)
            previews.removeAll(); regenerating = false
            if let sel = selectedItem { loadPreview(sel) }
        }
    }
    func clearPreviewCache() { Task { await previewService.clearCache(); previews.removeAll() } }

    // MARK: Management
    func requestDisable(_ item: EffectItem) {
        Task {
            let plan = await management.planDisable(item, sources: allDescriptors(), disabledOverride: disabledRootOverride.map { URL(fileURLWithPath: $0, isDirectory: true) })
            pending = PendingOperation(plan: plan, item: item)
        }
    }
    func requestRestore(_ item: EffectItem) {
        Task { pending = PendingOperation(plan: await management.planRestore(item, sources: allDescriptors()), item: item) }
    }
    func confirmPending() {
        guard let p = pending else { return }
        pending = nil
        Task {
            do {
                let out = try await management.execute(p.plan, confirmation: Confirmation(planID: p.plan.id))
                operationMessage = out.message
            } catch { operationMessage = "\(error)" }
            refreshJournal(); startScan()
        }
    }
    func cancelPending() { pending = nil }
    func refreshJournal() { journalEntries = journal.latestPerOperation().reversed() }

    // MARK: Diagnostics
    func exportDiagnostics(includePaths: Bool) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Export Here"; panel.message = "Choose where to save the diagnostic package (it is never uploaded)."
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let s = try DiagnosticsExporter(log: log, storage: storage, appInfo: appInfo).export(to: dir, includePaths: includePaths)
            operationMessage = "Diagnostics saved: \(s.url.path)"
            NSWorkspace.shared.activateFileViewerSelecting([s.url])
        } catch { operationMessage = "Could not export diagnostics: \(error)" }
    }
    func openLogs() { NSWorkspace.shared.activateFileViewerSelecting([storage.logFile]) }
    func copySessionID() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(log.sessionID, forType: .string) }
    func setDebug(_ on: Bool) { debugLogging = on; if on { log.enableDebug(for: 600) } else { log.disableDebug() } }
}

private extension Int { func nonZero(_ d: Int) -> Int { self > 0 ? self : d } }

struct RunningAppsProbe: RunningHostProbe {
    func runningHosts() -> [String] {
        if ProcessInfo.processInfo.environment["GEL_NO_HOSTS"] == "1" { return [] }   // verification hook: deterministic screenshots
        let names = Set(ManagementEngine.knownHostBundleNames)
        return NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }.filter { names.contains($0) }
    }
}
