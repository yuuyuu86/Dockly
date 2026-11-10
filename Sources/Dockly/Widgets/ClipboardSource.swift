import AppKit
import Combine

/// A short history of what you have copied.
///
/// Deliberately memory-only: clipboard contents are often passwords, tokens
/// and one-time codes, and writing them to disk would outlive the reason the
/// user copied them. Entries a password manager marks as concealed are skipped
/// outright, as is anything Dockly itself puts on the pasteboard.
final class ClipboardSource: ObservableObject {
    static let shared = ClipboardSource()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var copiedAt: Date

        var preview: String {
            let flat = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return flat.count > 60 ? String(flat.prefix(60)) + "…" : flat
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published var isPaused = false {
        didSet { if isPaused { /* leave history as it is */ } }
    }

    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressNext = false
    private let limit = 20

    /// The convention password managers use to say "do not record this".
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = everySecond(0.7) { [weak self] in self?.poll() }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if suppressNext { suppressNext = false; return }
        guard !isPaused else { return }

        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealed), !types.contains(Self.transient) else { return }
        guard let text = pasteboard.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Re-copying something already in the list moves it to the top rather
        // than duplicating it.
        entries.removeAll { $0.text == text }
        entries.insert(Entry(text: text, copiedAt: Date()), at: 0)
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
    }

    /// Puts an entry back on the pasteboard without recording it again.
    func copy(_ entry: Entry) {
        suppressNext = true
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        entries.removeAll { $0.id == entry.id }
        var moved = entry
        moved.copiedAt = Date()
        entries.insert(moved, at: 0)
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        entries.removeAll()
    }
}
