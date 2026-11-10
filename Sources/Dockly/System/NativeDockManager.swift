import Foundation
import AppKit

/// Reads and writes the *system* Dock's layout, so a Dockly setup can also
/// bring back the familiar Dock you had at the time.
enum NativeDockManager {

    private static let domain = "com.apple.dock"

    // MARK: Capture

    static func capture() -> NativeDockLayout {
        var layout = NativeDockLayout()
        let d = UserDefaults(suiteName: domain)

        layout.persistentApps = paths(in: d?.array(forKey: "persistent-apps"))
        layout.persistentOthers = paths(in: d?.array(forKey: "persistent-others"))
        if let n = d?.object(forKey: "tilesize") as? Double { layout.tileSize = n }
        if let n = d?.object(forKey: "largesize") as? Double { layout.largeSize = n }
        if let b = d?.object(forKey: "magnification") as? Bool { layout.magnification = b }
        if let s = d?.string(forKey: "orientation") { layout.orientation = s }
        if let b = d?.object(forKey: "autohide") as? Bool { layout.autohide = b }
        return layout
    }

    private static func paths(in array: [Any]?) -> [String] {
        guard let array else { return [] }
        return array.compactMap { entry in
            guard let dict = entry as? [String: Any],
                  let tile = dict["tile-data"] as? [String: Any],
                  let fileData = tile["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String
            else { return nil }
            if urlString.hasPrefix("file://") {
                return URL(string: urlString)?.path
            }
            return urlString
        }
    }

    // MARK: Apply

    static func apply(_ layout: NativeDockLayout) {
        var args: [[String]] = []

        let apps = layout.persistentApps.map(tilePlist(forApp:))
        let others = layout.persistentOthers.map(tilePlist(forOther:))

        args.append(["write", domain, "persistent-apps", "-array"] + apps)
        args.append(["write", domain, "persistent-others", "-array"] + others)
        if let t = layout.tileSize {
            args.append(["write", domain, "tilesize", "-int", String(Int(t))])
        }
        if let t = layout.largeSize {
            args.append(["write", domain, "largesize", "-int", String(Int(t))])
        }
        if let m = layout.magnification {
            args.append(["write", domain, "magnification", "-bool", m ? "true" : "false"])
        }
        if let o = layout.orientation {
            args.append(["write", domain, "orientation", "-string", o])
        }
        if let a = layout.autohide {
            args.append(["write", domain, "autohide", "-bool", a ? "true" : "false"])
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for a in args { _ = run("/usr/bin/defaults", a) }
            _ = run("/usr/bin/killall", ["Dock"])
        }
    }

    private static func tilePlist(forApp path: String) -> String {
        "<dict><key>tile-data</key><dict><key>file-data</key><dict>" +
        "<key>_CFURLString</key><string>\(escaped(path))</string>" +
        "<key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    }

    private static func tilePlist(forOther path: String) -> String {
        "<dict><key>tile-data</key><dict><key>file-data</key><dict>" +
        "<key>_CFURLString</key><string>\(escaped(path))</string>" +
        "<key>_CFURLStringType</key><integer>0</integer></dict>" +
        "<key>file-type</key><integer>2</integer></dict>" +
        "<key>tile-type</key><string>directory-tile</string></dict>"
    }

    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: Live system Dock controls

    /// Whether the system Dock is currently set to hide itself.
    static func systemDockIsHidden() -> Bool {
        UserDefaults(suiteName: domain)?.bool(forKey: "autohide") ?? false
    }

    /// True when the reveal delay is pinned open, which is what keeps the
    /// system Dock from popping up under Dockly's own hot edge.
    static func systemDockRevealPinned() -> Bool {
        guard let d = UserDefaults(suiteName: domain) else { return false }
        return (d.object(forKey: "autohide-delay") as? Double ?? 0) > 100
    }

    /// Hiding the Dock with `autohide` alone is not enough: it still slides
    /// back whenever the pointer reaches the same screen edge Dockly uses.
    /// Pinning the reveal delay wide open keeps it genuinely out of the way,
    /// and clearing the key puts the Dock back exactly as it was.
    ///
    /// `synchronously` matters at quit time, when the process can exit before
    /// a background write lands.
    static func setSystemDockHidden(_ hidden: Bool,
                                    suppressReveal: Bool = true,
                                    synchronously: Bool = false) {
        let wantDelayPinned = hidden && suppressReveal
        guard systemDockIsHidden() != hidden || systemDockRevealPinned() != wantDelayPinned
        else { return }

        let work = {
            _ = run("/usr/bin/defaults",
                    ["write", domain, "autohide", "-bool", hidden ? "true" : "false"])
            if wantDelayPinned {
                _ = run("/usr/bin/defaults",
                        ["write", domain, "autohide-delay", "-float", "1000"])
            } else {
                _ = run("/usr/bin/defaults", ["delete", domain, "autohide-delay"])
            }
            _ = run("/usr/bin/killall", ["Dock"])
        }
        if synchronously { work() }
        else { DispatchQueue.global(qos: .userInitiated).async(execute: work) }
    }

    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
