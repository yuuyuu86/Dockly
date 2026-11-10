import AppKit

/// Resolves and caches Finder icons. Dock tiles redraw constantly, so the
/// cache matters more than it looks.
final class IconProvider {
    static let shared = IconProvider()
    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in self?.purge() }
    }

    func purge() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }

    func icon(forPath path: String, side: CGFloat = 128) -> NSImage {
        let key = "\(path)#\(Int(side))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let image = NSWorkspace.shared.icon(forFile: path).resized(to: side)
        lock.lock(); cache[key] = image; lock.unlock()
        return image
    }

    func icon(forURL link: String, side: CGFloat = 128) -> NSImage {
        let key = "url:\(link)#\(Int(side))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        var image: NSImage
        if let url = URL(string: link),
           let handler = NSWorkspace.shared.urlForApplication(toOpen: url) {
            image = NSWorkspace.shared.icon(forFile: handler.path).resized(to: side)
        } else {
            image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil) ?? NSImage()
        }
        lock.lock(); cache[key] = image; lock.unlock()
        return image
    }

    /// Finds an app that has moved or been renamed, by bundle identifier and
    /// then by name, so a dock item does not turn into a question mark the
    /// first time something is reinstalled.
    func relocate(originalPath: String, bundleID: String?) -> String? {
        if FileManager.default.fileExists(atPath: originalPath) { return originalPath }

        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        let name = (originalPath as NSString).lastPathComponent
        return installedApps().first { ($0.path as NSString).lastPathComponent == name }?.path
    }

    /// Every app in /Applications and ~/Applications, for the picker.
    func installedApps() -> [(name: String, path: String)] {
        let fm = FileManager.default
        var roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        roots.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)
        var found: [(String, String)] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for e in entries where e.hasSuffix(".app") {
                found.append((String(e.dropLast(4)), root + "/" + e))
            }
        }
        return found.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}
