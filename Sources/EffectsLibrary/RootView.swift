// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: Theme.Metrics.sidebarMin, ideal: 230, max: 320)
        } detail: {
            LibraryGridView()
                .background(Theme.Palette.background)
                .inspector(isPresented: $state.inspectorVisible) {
                    InspectorView()
                        .inspectorColumnWidth(min: Theme.Metrics.inspectorMin, ideal: Theme.Metrics.inspectorIdeal, max: 420)
                }
        }
        .searchable(text: $state.query.searchText, placement: .toolbar, prompt: "Search name, vendor, effect, path")
        .onChange(of: state.query) { _, _ in state.dropSelectionIfHidden() }
        .toolbar { LibraryToolbar() }
        .sheet(item: $state.pending) { p in ConfirmOperationView(pending: p) }
        .sheet(item: $state.pendingConsent) { r in ConsentSheet(request: r) }
        .sheet(item: $state.pendingAssociate) { it in AssociateSheet(item: it) }
        .sheet(isPresented: Binding(get: { state.pendingBatch != nil }, set: { if !$0 { state.pendingBatch = nil } })) { BatchSheet(items: state.pendingBatch ?? []) }
        .alert("Scaner GDC", isPresented: Binding(get: { state.operationMessage != nil }, set: { if !$0 { state.operationMessage = nil } })) {
            Button("OK") { state.operationMessage = nil }
        } message: { Text(state.operationMessage ?? "") }
    }
}

struct LibraryToolbar: ToolbarContent {
    @Environment(AppState.self) private var state

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            @Bindable var state = state
            Menu {
                Picker("Vendor", selection: $state.query.vendor) {
                    Text("All vendors").tag(String?.none)
                    ForEach(state.vendors, id: \.self) { Text($0).tag(String?.some($0)) }
                    if state.hasUnknownVendor { Text("Unknown vendor").tag(String?.some(LibraryQuery.unknownVendor)) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Filter", systemImage: state.query.vendor == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Filter by vendor")

            Menu {
                Picker("Sort by", selection: $state.query.sortKey) {
                    ForEach(SortKey.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Order", selection: $state.query.ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort: \(state.query.sortKey.title)", systemImage: state.query.ascending ? "arrow.up" : "arrow.down")
            }
            .help("Sort items")
            .accessibilityLabel("Sort by \(state.query.sortKey.title), \(state.query.ascending ? "ascending" : "descending")")

            if state.isScanning {
                Button { state.cancelScan() } label: { Label("Cancel Scan", systemImage: "xmark.circle") }.help("Cancel the running scan")
            } else {
                Button { state.startScan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }.help("Rescan sources (⌘R)")
                    .disabled(state.origin == .mock)
            }
            Toggle(isOn: $state.inspectorVisible) {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector (⌥⌘I)")
        }
    }
}

struct ConfirmOperationView: View {
    @Environment(AppState.self) private var state
    let pending: PendingOperation
    var body: some View {
        let p = pending.plan
        VStack(alignment: .leading, spacing: 12) {
            Text(p.kind == .disable ? "Move “\(p.itemName)” to Disabled?" : "Restore “\(p.itemName)”?").typo(.title)
            Text("From").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            Text(p.from.path).typo(.mono).textSelection(.enabled)
            Text("To").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            Text(p.to.path).typo(.mono).textSelection(.enabled)
            if !p.blockers.isEmpty {
                ForEach(p.blockers, id: \.self) { Label($0, systemImage: "xmark.octagon").typo(.body).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true) }
            }
            ForEach(p.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").typo(.body).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true) }
            if p.isAllowed {
                Text("The item is not deleted and not modified. It can be restored from the Disabled list. Host applications pick up the change after they restart.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { state.cancelPending() }.keyboardShortcut(.cancelAction)
                Button(p.kind == .disable ? "Move to Disabled" : "Restore") { state.confirmPending() }
                    .keyboardShortcut(.defaultAction).disabled(!p.isAllowed)
            }
        }
        .padding(20).frame(width: 520)
    }
}
