import AppKit
import Combine

/// Tracks the apps macOS is running, so a dock can show them the way the
/// system Dock does.
final class RunningAppsMonitor: ObservableObject {
    static let shared = RunningAppsMonitor()

    struct Entry: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var isActive: Bool
        var isHidden: Bool
    }

    @Published private(set) var apps: [Entry] = []

    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.refresh()
            })
        }
        refresh()
    }

    func refresh() {
        let found = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> Entry? in
                guard let path = app.bundleURL?.path else { return nil }
                return Entry(path: path,
                             name: app.localizedName ?? (path as NSString).lastPathComponent,
                             isActive: app.isActive,
                             isHidden: app.isHidden)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard found != apps else { return }
        apps = found
    }

    // MARK: Acting on an app

    private func app(at path: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }
    }

    func isRunning(_ path: String) -> Bool { app(at: path) != nil }

    func quit(_ path: String) { app(at: path)?.terminate() }
    func forceQuit(_ path: String) { app(at: path)?.forceTerminate() }
    func hide(_ path: String) { app(at: path)?.hide() }
    func unhide(_ path: String) { app(at: path)?.unhide() }
    func isHidden(_ path: String) -> Bool { app(at: path)?.isHidden ?? false }

    func activate(_ path: String) {
        guard let running = app(at: path) else { return }
        running.unhide()
        if #available(macOS 14.0, *) { running.activate(options: [.activateAllWindows]) }
        else { running.activate(options: [.activateIgnoringOtherApps]) }
    }

    /// Opens a new window in an already-running app, or launches it.
    func newWindow(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Hands dropped files to an app, the way dropping on a Dock tile does.
    func open(_ files: [URL], with appPath: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: URL(fileURLWithPath: appPath),
                                configuration: config)
    }
}
