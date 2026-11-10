import Foundation
import Combine
import AppKit

/// Bridges to the macOS Shortcuts app via its command line tool.
final class ShortcutsRunner: ObservableObject {
    static let shared = ShortcutsRunner()

    @Published private(set) var names: [String] = []
    @Published private(set) var running: Set<String> = []

    private init() {}

    func reload() {
        DispatchQueue.global(qos: .utility).async {
            let out = NativeDockManager.run("/usr/bin/shortcuts", ["list"])
            let list = out.split(separator: "\n").map(String.init)
                .filter { !$0.isEmpty }.sorted()
            DispatchQueue.main.async { self.names = list }
        }
    }

    func run(_ name: String, completion: ((Bool) -> Void)? = nil) {
        guard !name.isEmpty else { completion?(false); return }
        running.insert(name)
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            p.arguments = ["run", name]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            var ok = false
            do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 }
            catch { ok = false }
            DispatchQueue.main.async {
                self.running.remove(name)
                completion?(ok)
            }
        }
    }

    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") { NSWorkspace.shared.open(url) }
    }
}
