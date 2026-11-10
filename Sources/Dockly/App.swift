import AppKit
import SwiftUI
import Darwin

@main
enum DocklyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DocklyStore.shared
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationHandlers()
        applySystemDockPreference()
        MenuBarController.shared.start()
        DockPanelController.shared.start()
        HotkeyCenter.shared.rebind(store: store)

        FocusMonitor.shared.start { [weak self] modeID in
            self?.focusChanged(to: modeID)
        }

        if store.library.settings.showAppBadges { BadgeReader.shared.start() }
        UpdateChecker.shared.start()

        DockWatcher.shared.start { [weak self] layout in
            self?.systemDockChanged(to: layout)
        }

        // A first run should show its hand: open settings so the user sees the
        // setups they were given.
        if !FileManager.default.fileExists(atPath: DocklyStore.libraryURL.path) {
            store.saveNow()
            SettingsWindowController.shared.show(tab: .setups)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.store.saveNow()
            }
    }

    /// Dockly replaces the Dock, so by default it tucks the system one away —
    /// remembering how it found things so quitting can put them back.
    func applySystemDockPreference() {
        store.library.settings.hideSystemDock = store.library.settings.mode.hidesSystemDock
        if store.library.settings.hideSystemDock {
            if store.library.settings.systemDockAutohideWas == nil {
                store.library.settings.systemDockAutohideWas = NativeDockManager.systemDockIsHidden()
            }
            NativeDockManager.setSystemDockHidden(true)
        } else if let original = store.library.settings.systemDockAutohideWas {
            NativeDockManager.setSystemDockHidden(original, suppressReveal: false)
            store.library.settings.systemDockAutohideWas = nil
        }
    }

    /// A SIGTERM (Activity Monitor's Quit, a logout, `pkill`) never reaches
    /// `applicationWillTerminate`, so the Dock has to be put back here too.
    private func installTerminationHandlers() {
        for signal in [SIGTERM, SIGINT, SIGHUP] {
            let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            source.setEventHandler { [weak self] in
                self?.restoreSystemDock()
                self?.store.saveNow()
                TimerEngine.shared.saveNow()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
            Darwin.signal(signal, SIG_IGN)
        }
    }

    private func restoreSystemDock() {
        guard store.library.settings.hideSystemDock,
              let original = store.library.settings.systemDockAutohideWas else { return }
        NativeDockManager.setSystemDockHidden(original, suppressReveal: false,
                                              synchronously: true)
    }

    /// Keeps a setup's saved macOS Dock in step when the user rearranges the
    /// real one by hand.
    private func systemDockChanged(to layout: NativeDockLayout) {
        guard store.library.settings.saveNativeDockChanges, !layout.isEmpty else { return }
        let id = store.activeProfile.id
        guard store.profile(id)?.appliesNativeDock == true else { return }
        store.update(id) { $0.nativeDock = layout }
    }

    private func focusChanged(to modeID: String?) {
        guard store.library.settings.followFocusModes else { return }
        guard let modeID else { return }
        guard let match = store.library.profiles.first(where: { $0.focusModeID == modeID })
        else { return }
        store.activate(match.id)
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreSystemDock()
        store.saveNow()
        TimerEngine.shared.saveNow()
        HotkeyCenter.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}
