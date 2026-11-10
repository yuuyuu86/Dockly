import AppKit

enum AirDropService {
    static var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    /// Opens the AirDrop sheet for the given items, anchored to `view` so the
    /// picker appears next to the dock tile the user dropped onto.
    static func send(_ items: [Any], from view: NSView?) {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else {
            NSSound.beep(); return
        }
        service.subject = "Shared from Dockly"
        service.perform(withItems: items)
    }

    /// Opens Finder's AirDrop window — the same place ⇧⌘R goes.
    static func openAirDropWindow() {
        guard let url = URL(string: "nwnode://domain-AirDrop") else { return }
        NSWorkspace.shared.open(url)
    }
}
