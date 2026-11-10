import AppKit
import ApplicationServices
import CoreServices
import Combine

/// Reads the notification badges macOS draws on system Dock tiles.
///
/// There is no public API for another app's badge, so Dockly asks the Dock
/// itself through Accessibility — the same route a screen reader takes. Without
/// that permission badges are simply not shown; nothing else degrades.
final class BadgeReader: ObservableObject {
    static let shared = BadgeReader()

    /// Badge text keyed by application path.
    @Published private(set) var badges: [String: String] = [:]
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?
    private var running = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = everySecond(4) { [weak self] in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        badges = [:]
    }

    /// Asks macOS for Accessibility access, showing the system prompt once.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        isTrusted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    func badge(forPath path: String) -> String? { badges[path] }

    // MARK: Reading

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        guard trusted, !running else {
            if !trusted && !badges.isEmpty { badges = [:] }
            return
        }
        running = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.readDockBadges()
            DispatchQueue.main.async {
                self?.running = false
                guard let self, found != self.badges else { return }
                self.badges = found
            }
        }
    }

    private static func readDockBadges() -> [String: String] {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }

        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let children = copyChildren(app) else { return [:] }

        var out: [String: String] = [:]
        // The Dock exposes one AXList of tiles; badges hang off each tile.
        for child in children {
            guard role(of: child) == kAXListRole as String,
                  let tiles = copyChildren(child) else { continue }
            for tile in tiles {
                guard let label = string(tile, "AXStatusLabel"), !label.isEmpty,
                      let path = applicationPath(of: tile) else { continue }
                out[path] = label
            }
        }
        return out
    }

    private static func applicationPath(of tile: AXUIElement) -> String? {
        // Some systems expose the tile's URL outright.
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(tile, kAXURLAttribute as CFString, &value) == .success {
            if let url = value as? NSURL, let path = url.path { return path }
            if let raw = value as? String { return URL(string: raw)?.path ?? raw }
        }
        // Otherwise the only handle is the tile's title, which macOS shows
        // localised ("リマインダー", not "Reminders"), so both lookups below
        // compare display names rather than file names.
        guard let title = string(tile, kAXTitleAttribute as String) else { return nil }
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == title })?.bundleURL?.path {
            return running
        }
        return installedAppsByDisplayName()[title]
    }

    private static var displayNameCache: [String: String] = [:]
    private static var displayNameCachedAt: Date = .distantPast
    private static let cacheLock = NSLock()

    /// Localised display name → application path, refreshed occasionally so a
    /// newly installed app is picked up without a relaunch.
    ///
    /// Dock tiles are titled in the user's language ("リマインダー", not
    /// "Reminders"), and neither the file name nor `Bundle` gives that name
    /// reliably — Spotlight's `kMDItemDisplayName` does.
    private static func installedAppsByDisplayName() -> [String: String] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if Date().timeIntervalSince(displayNameCachedAt) < 300, !displayNameCache.isEmpty {
            return displayNameCache
        }
        var map: [String: String] = [:]
        let fm = FileManager.default
        for (_, path) in IconProvider.shared.installedApps() {
            if let item = MDItemCreate(nil, path as CFString),
               let display = MDItemCopyAttribute(item, kMDItemDisplayName) as? String {
                map[trimApp(display)] = path
            }
            // Also key the plain file name, for the unlocalised case.
            map[trimApp((path as NSString).lastPathComponent)] = path
        }
        _ = fm
        displayNameCache = map
        displayNameCachedAt = Date()
        return map
    }

    private static func trimApp(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private static func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute as String)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }
}
