import AppKit
import Combine

/// The most-recently-used apps, in the order you last switched to them —
/// the same idea as the system Dock's recents section.
final class RecentAppsSource: ObservableObject {
    static let shared = RecentAppsSource()

    struct Entry: Identifiable, Hashable {
        var id: String { path }
        var path: String
        var name: String
        var isRunning: Bool
    }

    @Published private(set) var apps: [Entry] = []

    /// Paths, newest first. Kept separately from `apps` so the order survives
    /// a relaunch even for apps that are no longer running.
    private var order: [String] = []
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?

    private static let limit = 24

    private static var stateURL: URL {
        DocklyStore.supportDirectory.appendingPathComponent("recent-apps.json")
    }

    private init() {
        restore()
        let center = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication {
                    self?.note(app)
                }
                self?.rebuild()
            })
        }
        // Seed with whatever is already running, so the widget is useful from
        // the first launch rather than after the first app switch.
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            note(app, appendOnly: true)
        }
        rebuild()
    }

    private func note(_ app: NSRunningApplication, appendOnly: Bool = false) {
        guard app.activationPolicy == .regular,
              let path = app.bundleURL?.path,
              path != Bundle.main.bundlePath else { return }
        if appendOnly {
            if !order.contains(path) { order.append(path) }
        } else {
            order.removeAll { $0 == path }
            order.insert(path, at: 0)
        }
        if order.count > Self.limit { order = Array(order.prefix(Self.limit)) }
        scheduleSave()
    }

    private func rebuild() {
        let running = Set(NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleURL?.path })
        let fm = FileManager.default
        let found = order
            .filter { fm.fileExists(atPath: $0) }
            .map { path in
                Entry(path: path,
                      name: RecentAppsSource.displayName(for: path),
                      isRunning: running.contains(path))
            }
        guard found != apps else { return }
        apps = found
    }

    /// The first `count` recents, optionally skipping anything already pinned.
    func top(_ count: Int, excluding pinned: Set<String> = []) -> [Entry] {
        Array(apps.filter { !pinned.contains($0.path) }.prefix(max(1, count)))
    }

    func activate(_ path: String) {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleURL?.path == path }) {
            running.unhide()
            if #available(macOS 14.0, *) { running.activate(options: [.activateAllWindows]) }
            else { running.activate(options: [.activateIgnoringOtherApps]) }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: config)
    }

    func clear() {
        order.removeAll()
        apps.removeAll()
        scheduleSave()
    }

    private static func displayName(for path: String) -> String {
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleURL?.path == path }), let name = running.localizedName {
            return name
        }
        return (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Persistence

    private func restore() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let saved = try? JSONDecoder.dockly.decode([String].self, from: data)
        else { return }
        order = saved
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = try? JSONEncoder.dockly.encode(self.order) else { return }
            try? data.write(to: Self.stateURL, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
