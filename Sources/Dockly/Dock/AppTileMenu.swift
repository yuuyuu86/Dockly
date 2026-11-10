import SwiftUI
import AppKit

/// The tile menu, laid out the way the system Dock lays it out: the app's
/// windows, then Options, then Show All Windows / Hide / Quit.
struct AppTileMenu: View {
    var path: String
    var isPinned: Bool
    var onPin: () -> Void
    var onUnpin: () -> Void

    @ObservedObject private var running = RunningAppsMonitor.shared

    private var isRunning: Bool { AppActions.isRunning(path) }

    var body: some View {
        let windows = isRunning ? AppActions.windows(forPath: path) : []

        if !windows.isEmpty {
            ForEach(windows) { window in
                Button(window.title) {
                    AppActions.raise(windowTitled: window.title, ofApp: path)
                }
            }
            Divider()
        }

        Menu(L("Options")) {
            if isPinned {
                Button(L("Remove from Dock"), action: onUnpin)
            } else {
                Button(L("Keep in Dock"), action: onPin)
            }
            Button(AppActions.isLoginItem(path) ? L("Don't Open at Login")
                                                : L("Open at Login")) {
                AppActions.setLoginItem(path, !AppActions.isLoginItem(path))
            }
            Button(L("Show in Finder")) { AppActions.showInFinder(path) }
        }

        if isRunning {
            Divider()
            Button(L("Show All Windows")) { AppActions.activate(path) }
            Button(AppActions.isHidden(path) ? L("Show") : L("Hide")) {
                AppActions.isHidden(path) ? AppActions.unhide(path) : AppActions.hide(path)
            }
            Divider()
            Button(L("Quit")) { AppActions.quit(path) }
            Button(L("Force Quit")) { AppActions.forceQuit(path) }
        } else {
            Divider()
            Button(L("Open")) { AppActions.open(path) }
        }
    }
}
