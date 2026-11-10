import Foundation
import Combine

struct FocusMode: Identifiable, Hashable {
    var id: String          // mode identifier, e.g. com.apple.focus.work
    var name: String
    var symbol: String
}

/// Watches macOS Focus. When the active Focus changes, any Dockly setup bound
/// to that Focus takes over automatically.
final class FocusMonitor: ObservableObject {
    static let shared = FocusMonitor()

    @Published private(set) var activeModeID: String?
    @Published private(set) var availableModes: [FocusMode] = []

    private var source: DispatchSourceFileSystemObject?
    private var fd: CInt = -1
    private var poll: Timer?
    private var onChange: ((String?) -> Void)?

    private var dndDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }
    private var assertionsURL: URL { dndDirectory.appendingPathComponent("Assertions.json") }
    private var configurationsURL: URL { dndDirectory.appendingPathComponent("ModeConfigurations.json") }

    private init() {}

    func start(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
        reloadModes()
        reloadActive(notify: false)
        watch()
        // Belt and braces: the DB file is rewritten atomically, which can drop
        // the kqueue watch, so a slow poll keeps things honest.
        poll = everySecond(3) { [weak self] in
            self?.reloadActive(notify: true)
        }
    }

    private func watch() {
        fd = open(dndDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend],
            queue: .main)
        s.setEventHandler { [weak self] in self?.reloadActive(notify: true) }
        s.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
        }
        s.resume()
        source = s
    }

    // MARK: Reading Apple's Focus database

    func reloadModes() {
        guard let data = try? Data(contentsOf: configurationsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["data"] as? [[String: Any]]
        else { availableModes = Self.fallbackModes; return }

        var modes: [FocusMode] = []
        for entry in list {
            guard let configs = entry["modeConfigurations"] as? [String: Any] else { continue }
            for (id, raw) in configs {
                guard let cfg = raw as? [String: Any],
                      let mode = cfg["mode"] as? [String: Any] else { continue }
                let name = (mode["name"] as? String) ?? id
                let symbol = (mode["symbolImageName"] as? String) ?? "moon.fill"
                modes.append(FocusMode(id: id, name: name, symbol: symbol))
            }
        }
        availableModes = modes.isEmpty ? Self.fallbackModes
                                       : modes.sorted { $0.name < $1.name }
    }

    private func reloadActive(notify: Bool) {
        let id = currentModeID()
        guard id != activeModeID else { return }
        activeModeID = id
        if notify { onChange?(id) }
    }

    private func currentModeID() -> String? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let store = root["data"] as? [[String: Any]],
              let first = store.first,
              let records = first["storeAssertionRecords"] as? [[String: Any]]
        else { return nil }

        for record in records {
            if let details = record["assertionDetails"] as? [String: Any],
               let id = details["assertionDetailsModeIdentifier"] as? String {
                return id
            }
        }
        return nil
    }

    func name(for id: String) -> String {
        availableModes.first { $0.id == id }?.name ?? id
    }

    static let fallbackModes: [FocusMode] = [
        FocusMode(id: "com.apple.donotdisturb.mode.default", name: "Do Not Disturb", symbol: "moon.fill"),
        FocusMode(id: "com.apple.focus.work", name: "Work", symbol: "briefcase.fill"),
        FocusMode(id: "com.apple.focus.personal", name: "Personal", symbol: "person.fill"),
        FocusMode(id: "com.apple.sleep.sleep-mode", name: "Sleep", symbol: "bed.double.fill"),
        FocusMode(id: "com.apple.focus.reading", name: "Reading", symbol: "book.fill"),
        FocusMode(id: "com.apple.focus.gaming", name: "Gaming", symbol: "gamecontroller.fill"),
        FocusMode(id: "com.apple.focus.fitness", name: "Fitness", symbol: "figure.run"),
        FocusMode(id: "com.apple.focus.mindfulness", name: "Mindfulness", symbol: "brain.head.profile"),
        FocusMode(id: "com.apple.focus.driving", name: "Driving", symbol: "car.fill"),
    ]
}
