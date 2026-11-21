// Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
import SwiftUI
import AppKit
import EffectsLibraryEngine

/// Update flow state. Checking is automatic (can be turned off); downloading/installing only after "Update Now".
enum UpdateUIState: Equatable {
    case idle, checking, upToDate(String)
    case available(UpdateOffer)
    case working(String, Double?)          // phase text, fraction
    case failed(String)
    case installedRestarting(String)
}
struct UpdateSheetItem: Identifiable { let id = UUID() }

extension AppState {
    static let dismissedKey = "dismissedUpdateVersion"

    /// At launch: silent check (failures only go to the log). A newer version shows the sheet once per version.
    func checkForUpdatesAtLaunch() {
        guard checkUpdatesAtLaunch, origin != .mock else { return }
        Task { await runCheck(manual: false) }
    }
    func checkForUpdatesManually() { updateSheet = UpdateSheetItem(); Task { await runCheck(manual: true) } }

    private func runCheck(manual: Bool) async {
        if case .working = updateState { return }
        updateState = .checking
        let r = await updater.check()
        switch r {
        case .available(let o):
            updateState = .available(o)
            let dismissed = UserDefaults.standard.string(forKey: Self.dismissedKey) == o.version
            if manual || o.mandatory || !dismissed { updateSheet = UpdateSheetItem() }
        case .upToDate(let i, _): updateState = manual ? .upToDate(i) : .idle
        case .failed(let f):
            log.warning("update", "update.check.failed", f.description)
            updateState = manual ? .failed(f.description) : .idle        // at launch a failure is not announced as "up to date" nor as an error dialog
        }
    }

    func updateLater() {
        if case .available(let o) = updateState { UserDefaults.standard.set(o.version, forKey: Self.dismissedKey); updateState = .idle }
        updateSheet = nil
    }

    func updateNow() {
        guard case .available(let offer) = updateState else { return }
        updateState = .working("Downloading…", 0)
        let target = Bundle.main.bundleURL
        updateTask = Task { [self] in
            let work = storage.caches.appendingPathComponent("update", isDirectory: true)
            let res = await updater.install(offer, target: target, workDir: work, relaunch: true) { phase in
                Task { @MainActor in
                    switch phase {
                    case .downloading(let d, let t): self.updateState = .working("Downloading…", t.map { Double(d) / Double($0) })
                    case .verifying: self.updateState = .working("Verifying the download…", nil)
                    case .installing: self.updateState = .working("Installing…", nil)
                    case .done: break
                    }
                }
            }
            switch res {
            case .success(let v): updateState = .installedRestarting(v); try? await Task.sleep(nanoseconds: 800_000_000); NSApplication.shared.terminate(nil)
            case .failure(.cancelled): updateState = .available(offer)
            case .failure(let f): updateState = .failed(f.description)
            }
        }
    }
    func cancelUpdate() { updateTask?.cancel() }
}

struct UpdateSheet: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates").typo(.title)
            Text("Installed version: \(state.appInfo.version) (\(state.appInfo.build))").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            switch state.updateState {
            case .checking, .idle: HStack { ProgressView().controlSize(.small); Text("Checking…").typo(.body) }
            case .upToDate(let v): Text("You are up to date (version \(v)).").typo(.body)
            case .failed(let m):
                Label("Could not check or install: \(m)", systemImage: "exclamationmark.triangle").typo(.body).foregroundStyle(Theme.Palette.warning).fixedSize(horizontal: false, vertical: true)
                Text("The installed version was not changed. You can also download the latest release from the project page.").typo(.caption).foregroundStyle(Theme.Palette.textSecondary)
            case .available(let o):
                Text("Version \(o.version) is available.").typo(.body).bold()
                if !o.changes.isEmpty { Text(o.changes).typo(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                Text("“Update Now” downloads the new version from GitHub, checks that it is signed by the same developer with the same app identity, replaces this app and reopens it. Your settings and data are kept. Nothing is downloaded until you choose.")
                    .typo(.caption).foregroundStyle(Theme.Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            case .working(let t, let f):
                Text(t).typo(.body)
                if let f { ProgressView(value: min(max(f, 0), 1)) } else { ProgressView().controlSize(.small) }
            case .installedRestarting(let v): Text("Version \(v) installed. Reopening…").typo(.body)
            }
            HStack { Spacer()
                switch state.updateState {
                case .available(let o):
                    if !o.mandatory { Button("Later") { state.updateLater() }.keyboardShortcut(.cancelAction) } else { Button("Close") { state.updateSheet = nil } }
                    Button("Update Now") { state.updateNow() }.keyboardShortcut(.defaultAction)
                case .working: Button("Cancel") { state.cancelUpdate() }.keyboardShortcut(.cancelAction)
                case .installedRestarting: EmptyView()
                default: Button("Close") { state.updateSheet = nil }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(20).frame(width: 480)
    }
}
