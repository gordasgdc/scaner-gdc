// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import EffectsLibraryCore

@main
struct EffectsLibraryApp: App {
    @State private var state = AppState()
    init() {
        if ProcessInfo.processInfo.environment["GEL_SHOW_ABOUT"] == "1" {   // verification hook
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApplication.shared.orderFrontStandardAboutPanel(nil) }
        }
    }

    var body: some Scene {
        Window("Scaner GDC", id: "main") {
            RootView()
                .environment(state)
                .environment(\.textScale, state.textSize.scale)
                .preferredColorScheme(state.appearance.colorScheme)
                .frame(minWidth: Theme.Metrics.windowMinWidth, minHeight: Theme.Metrics.windowMinHeight)
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Scaner GDC") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Scaner GDC",
                        .credits: NSAttributedString(string: "Scaner GDC — creat de Cristi Gordaș (GDC).\n\nInventory and preview of OFX, LUT, DCTL, VST3, Audio Unit and VST resources. Read-only scanning; every change is recoverable.\n\nFree software: GNU GPL v3 only, with additional terms (§7) — see LICENSE and LICENSE-ADDITIONAL-TERMS.md in the source repository. Name and logo: see branding/BRANDING.md.")
                    ])
                }
            }
            CommandGroup(after: .appInfo) { Button("Check for Updates…") { state.checkForUpdatesManually() } }
            LibraryCommands(state: state)
        }

        Settings {
            SettingsView()
                .environment(state)
                .environment(\.textScale, state.textSize.scale)
                .preferredColorScheme(state.appearance.colorScheme)
        }
    }
}

struct LibraryCommands: Commands {
    let state: AppState
    var body: some Commands {
        CommandMenu("Library") {
            Button("Rescan Sources") { state.startScan() }.keyboardShortcut("r", modifiers: .command).disabled(state.isScanning || state.origin == .mock)
            Button("Cancel Scan") { state.cancelScan() }.keyboardShortcut(".", modifiers: .command).disabled(!state.isScanning)
            Button("Add Custom Source…") { state.addCustomSource() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Reveal Source Folders in Finder") { state.revealSourceFolders() }.keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("Search Cover and Details") { if let i = state.selectedItem { state.findCoverAndDetails(i) } }.disabled(state.selectedItem == nil)
            Button("Fill Items Without Cover…") { state.prepareFill(state.selectedItem.map { [$0] } ?? state.activeItems) }
            Divider()
            Button("Export Diagnostics…") { state.exportDiagnostics(includePaths: false) }
            Button("Show Log in Finder") { state.openLogs() }
            Button("Copy Session ID") { state.copySessionID() }
            Divider()
            Toggle("Show Previews", isOn: Binding(get: { state.showPreviews }, set: { state.showPreviews = $0 }))
                .keyboardShortcut("p", modifiers: [.command, .option])
            Toggle("Show Inspector", isOn: Binding(get: { state.inspectorVisible }, set: { state.inspectorVisible = $0 }))
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
