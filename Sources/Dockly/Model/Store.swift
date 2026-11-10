import SwiftUI
import Combine
import AppKit

/// The single source of truth. Owns the library, persists it, and broadcasts
/// changes to the dock panel, the menu bar and the settings window.
final class DocklyStore: ObservableObject {
    static let shared = DocklyStore()

    @Published var library: DockLibrary { didSet { scheduleSave() } }
    /// Set while a switch overlay should be on screen.
    @Published var switchBanner: String?

    private var saveWork: DispatchWorkItem?

    // MARK: Locations

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Dockly", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static var libraryURL: URL { supportDirectory.appendingPathComponent("library.json") }
    static var backupsDirectory: URL {
        let u = supportDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Init

    private init() {
        if let data = try? Data(contentsOf: Self.libraryURL),
           let lib = try? JSONDecoder.dockly.decode(DockLibrary.self, from: data) {
            library = lib
        } else {
            library = Self.starterLibrary()
        }
        if library.profiles.isEmpty { library = Self.starterLibrary() }
        if library.activeProfileID == nil { library.activeProfileID = library.profiles.first?.id }
        migrate()
        repairMovedItems()
    }

    /// Re-points app items whose bundle has moved since the setup was made.
    private func repairMovedItems() {
        var changed = false
        for (pi, profile) in library.profiles.enumerated() {
            for (ii, item) in profile.items.enumerated() {
                guard item.kind == .app, let path = item.path,
                      !FileManager.default.fileExists(atPath: path) else { continue }
                guard let found = IconProvider.shared.relocate(originalPath: path,
                                                               bundleID: item.bundleID)
                else { continue }
                library.profiles[pi].items[ii].path = found
                changed = true
            }
        }
        if changed { saveNow() }
    }

    /// Brings older libraries up to the current defaults.
    private func migrate() {
        if library.version < 2 {
            for i in library.profiles.indices
            where library.profiles[i].appearance.hideMode == .never {
                library.profiles[i].appearance.hideMode = .auto
            }
            library.settings.hideSystemDock = true
            library.version = 2
        }
        if library.version < 3 {
            library.settings.mode = library.settings.hideSystemDock ? .custom : .both
            library.version = 3
        }
    }

    // MARK: Active profile

    var activeProfile: DockProfile {
        get { library.activeProfile ?? DockProfile() }
        set {
            guard let i = library.profiles.firstIndex(where: { $0.id == newValue.id }) else { return }
            library.profiles[i] = newValue
        }
    }

    var activeIndex: Int {
        library.profiles.firstIndex { $0.id == library.activeProfileID } ?? 0
    }

    func profile(_ id: UUID) -> DockProfile? { library.profiles.first { $0.id == id } }

    func update(_ id: UUID, _ mutate: (inout DockProfile) -> Void) {
        guard let i = library.profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&library.profiles[i])
    }

    // MARK: Switching

    func activate(_ id: UUID, announce: Bool = true) {
        guard let p = profile(id) else { return }
        let changed = library.activeProfileID != id
        library.activeProfileID = id

        if p.appliesNativeDock, let layout = p.nativeDock, !layout.isEmpty {
            NativeDockManager.apply(layout)
        }
        if changed && announce && library.settings.showSwitchOverlay {
            showBanner(p.name)
        }
        if changed && library.settings.hapticOnSwitch {
            NSHapticFeedbackManager.defaultPerformer
                .perform(.generic, performanceTime: .now)
        }
        objectWillChange.send()
    }

    func cycle(by delta: Int) {
        guard library.profiles.count > 1 else { return }
        let n = library.profiles.count
        let next = ((activeIndex + delta) % n + n) % n
        activate(library.profiles[next].id)
    }

    private func showBanner(_ text: String) {
        switchBanner = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            if self?.switchBanner == text { self?.switchBanner = nil }
        }
    }

    // MARK: Profile management

    @discardableResult
    func addProfile(named name: String = "New Setup") -> DockProfile {
        var p = DockProfile(name: name)
        p.accent = Color.docklyPalette.randomElement() ?? "#5B8CFF"
        library.profiles.append(p)
        return p
    }

    func duplicate(_ id: UUID) {
        guard var p = profile(id) else { return }
        p.id = UUID()
        p.name += " Copy"
        p.hotkey = nil
        p.focusModeID = nil
        p.items = p.items.map { var i = $0; i.id = UUID(); return i }
        library.profiles.append(p)
    }

    /// Asks before throwing a setup away; there is no undo for it.
    @discardableResult
    func confirmDelete(_ id: UUID) -> Bool {
        guard let profile = profile(id), library.profiles.count > 1 else { return false }
        let alert = NSAlert()
        alert.messageText = L("Delete “%@”?", profile.name)
        alert.informativeText = L("Its dock items and appearance go with it. This can't be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Delete"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        makeBackup(note: "before-delete")
        delete(id)
        return true
    }

    func delete(_ id: UUID) {
        guard library.profiles.count > 1 else { return }
        library.profiles.removeAll { $0.id == id }
        if library.activeProfileID == id { library.activeProfileID = library.profiles.first?.id }
    }

    // MARK: Items

    func addItem(_ item: DockItem, to profileID: UUID? = nil, at index: Int? = nil) {
        let pid = profileID ?? library.activeProfileID
        guard let pid, let i = library.profiles.firstIndex(where: { $0.id == pid }) else { return }
        if let index, index <= library.profiles[i].items.count {
            library.profiles[i].items.insert(item, at: index)
        } else {
            library.profiles[i].items.append(item)
        }
    }

    func removeItem(_ itemID: UUID, from profileID: UUID) {
        update(profileID) { $0.items.removeAll { $0.id == itemID } }
    }

    func moveItem(in profileID: UUID, from: Int, to: Int) {
        update(profileID) { p in
            guard from >= 0, from < p.items.count else { return }
            let item = p.items.remove(at: from)
            p.items.insert(item, at: min(max(0, to), p.items.count))
        }
    }

    // MARK: Widget state (things widgets need to remember)

    func widgetSetting(_ itemID: UUID, _ key: String) -> String? {
        for p in library.profiles {
            if let it = p.items.first(where: { $0.id == itemID }) { return it.widget?.settings[key] }
        }
        return nil
    }

    func setWidgetSetting(_ itemID: UUID, _ key: String, _ value: String?) {
        for (pi, p) in library.profiles.enumerated() {
            guard let ii = p.items.firstIndex(where: { $0.id == itemID }) else { continue }
            library.profiles[pi].items[ii].widget?.settings[key] = value
            return
        }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        guard let data = try? JSONEncoder.dockly.encode(library) else { return }
        try? data.write(to: Self.libraryURL, options: .atomic)
    }

    // MARK: Backup / transfer

    @discardableResult
    func exportLibrary(to url: URL) -> Bool {
        guard let data = try? JSONEncoder.dockly.encode(library) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    enum ImportMode { case replace, merge }

    @discardableResult
    func importLibrary(from url: URL, mode: ImportMode) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let incoming = try? JSONDecoder.dockly.decode(DockLibrary.self, from: data)
        else { return false }
        makeBackup(note: "before-import")
        switch mode {
        case .replace:
            library = incoming
            if library.activeProfileID == nil { library.activeProfileID = library.profiles.first?.id }
        case .merge:
            var fresh = incoming.profiles
            for i in fresh.indices {
                fresh[i].id = UUID()
                fresh[i].hotkey = nil
                fresh[i].items = fresh[i].items.map { var it = $0; it.id = UUID(); return it }
            }
            library.profiles.append(contentsOf: fresh)
        }
        return true
    }

    @discardableResult
    func makeBackup(note: String = "manual") -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = Self.backupsDirectory.appendingPathComponent("Dockly-\(note)-\(stamp).json")
        return exportLibrary(to: url) ? url : nil
    }

    func backups() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: Self.backupsDirectory,
                                                      includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            } ?? []
    }

    // MARK: Starter content

    static func starterLibrary() -> DockLibrary {
        var work = DockProfile(name: "Work", symbol: "briefcase.fill", accent: "#5B8CFF")
        work.items = [
            .app(path: "/System/Applications/Mail.app"),
            .app(path: "/System/Applications/Calendar.app"),
            .app(path: "/System/Applications/Notes.app"),
            DockItem(kind: .divider),
            .widget(.clock),
            .widget(.focusTimer),
            .widget(.calendar),
        ]

        var personal = DockProfile(name: "Personal", symbol: "house.fill", accent: "#34C759")
        personal.items = [
            .app(path: "/System/Applications/Music.app"),
            .app(path: "/System/Applications/Photos.app"),
            .app(path: "/System/Applications/Messages.app"),
            DockItem(kind: .divider),
            .widget(.nowPlaying),
            .widget(.weather),
            .widget(.reminders),
        ]

        var focus = DockProfile(name: "Focus", symbol: "moon.fill", accent: "#BF5AF2")
        focus.appearance.iconSize = 40
        focus.items = [
            .widget(.focusTimer),
            .widget(.timeProgress),
            .widget(.stickyNote),
            .widget(.hydration),
        ]

        var lib = DockLibrary(profiles: [work, personal, focus])
        lib.activeProfileID = work.id
        return lib
    }
}

extension JSONEncoder {
    static var dockly: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var dockly: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
