import AppKit
import ApplicationServices
import CoreGraphics

/// The things the system Dock's tile menu can do to an app.
enum AppActions {

    // MARK: Windows

    struct WindowRef: Identifiable, Hashable {
        var id: CGWindowID
        var title: String
    }

    /// Titled, on-screen windows belonging to the app at `path`.
    static func windows(forPath path: String) -> [WindowRef] {
        guard let app = running(path) else { return [] }
        let pid = app.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        var seen = Set<String>()
        var out: [WindowRef] = []
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let title = w[kCGWindowName as String] as? String,
                  !title.isEmpty, !seen.contains(title)
            else { continue }
            seen.insert(title)
            out.append(WindowRef(id: w[kCGWindowNumber as String] as? CGWindowID ?? 0,
                                 title: title))
        }
        return out
    }

    /// Brings one window forward. Needs Accessibility; without it the app is
    /// simply activated, which is still the useful half of the action.
    static func raise(windowTitled title: String, ofApp path: String) {
        guard let app = running(path) else { return }
        defer { activate(path) }
        guard AXIsProcessTrusted() else { return }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString,
                                            &value) == .success,
              let windows = value as? [AXUIElement] else { return }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString,
                                                &titleValue) == .success,
                  (titleValue as? String) == title else { continue }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                         kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    // MARK: Lifecycle

    static func running(_ path: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == path }
    }

    static func isRunning(_ path: String) -> Bool { running(path) != nil }
    static func isHidden(_ path: String) -> Bool { running(path)?.isHidden ?? false }

    static func activate(_ path: String) {
        guard let app = running(path) else { open(path); return }
        app.unhide()
        if #available(macOS 14.0, *) { app.activate(options: [.activateAllWindows]) }
        else { app.activate(options: [.activateIgnoringOtherApps]) }
    }

    static func open(_ path: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: config)
    }

    static func hide(_ path: String) { running(path)?.hide() }
    static func unhide(_ path: String) { running(path)?.unhide() }
    static func quit(_ path: String) { running(path)?.terminate() }
    static func forceQuit(_ path: String) { running(path)?.forceTerminate() }

    static func showInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Login items

    /// System Events owns the login items list; there is no public API for
    /// adding another app to it.
    static func isLoginItem(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
        let script = """
        tell application "System Events" to return (exists login item "\(escape(name))")
        """
        return runScript(script)?.booleanValue ?? false
    }

    static func setLoginItem(_ path: String, _ enabled: Bool) {
        let name = (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
        let script: String
        if enabled {
            script = """
            tell application "System Events" to make login item at end \
            with properties {path:"\(escape(path))", hidden:false}
            """
        } else {
            script = """
            tell application "System Events" to delete login item "\(escape(name))"
            """
        }
        DispatchQueue.global(qos: .userInitiated).async { _ = runScript(script) }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    @discardableResult
    private static func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Dockly: AppleScript failed — \(error)") }
        return result
    }
}
