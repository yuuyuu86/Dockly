import AppKit
import Darwin
import Combine

/// The Trash tile — how full it is, what it looks like, and what dropping on
/// it does.
final class TrashService: ObservableObject {
    static let shared = TrashService()

    @Published private(set) var itemCount = 0

    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1

    var url: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash", isDirectory: true)
    }

    var isEmpty: Bool { itemCount == 0 }

    private init() {
        refresh()
        watch()
        timer = everySecond(15) { [weak self] in self?.refresh() }
    }

    private func watch() {
        fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        s.setEventHandler { [weak self] in self?.refresh() }
        s.setCancelHandler { [weak self] in if let fd = self?.fd, fd >= 0 { close(fd) } }
        s.resume()
        source = s
    }

    func refresh() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        guard contents.count != itemCount else { return }
        itemCount = contents.count
    }

    var icon: NSImage {
        let name: NSImage.Name = isEmpty ? NSImage.trashEmptyName : NSImage.trashFullName
        return NSImage(named: name) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    func open() { NSWorkspace.shared.open(url) }

    /// Moves dropped files to the Trash, with the usual sound.
    func moveToTrash(_ files: [URL]) {
        guard !files.isEmpty else { return }
        var moved = 0
        for file in files {
            do {
                try FileManager.default.trashItem(at: file, resultingItemURL: nil)
                moved += 1
            } catch {
                NSLog("Dockly: could not trash \(file.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        if moved > 0 { NSSound(named: "Bottle")?.play() }
        refresh()
    }

    /// Asks first — emptying the Trash cannot be undone.
    func empty() {
        guard !isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("Empty the Trash?")
        alert.informativeText = L("%d items will be deleted immediately. You can't undo this.", itemCount)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Empty Trash"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Finder owns the Trash; asking it keeps the behaviour identical to
        // emptying from the system Dock.
        let script = "tell application \"Finder\" to empty trash"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            DispatchQueue.main.async { self.refresh() }
        }
    }
}
