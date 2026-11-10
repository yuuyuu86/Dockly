import Foundation
import Combine

/// Notices when you rearrange the *system* Dock yourself, so the active setup
/// can keep its saved layout up to date instead of quietly going stale.
final class DockWatcher: ObservableObject {
    static let shared = DockWatcher()

    private var timer: Timer?
    private var lastSignature: String?
    private var onChange: ((NativeDockLayout) -> Void)?

    private init() {}

    func start(onChange: @escaping (NativeDockLayout) -> Void) {
        self.onChange = onChange
        lastSignature = signature(of: NativeDockManager.capture())
        guard timer == nil else { return }
        timer = everySecond(5) { [weak self] in self?.check() }
    }

    private func check() {
        let layout = NativeDockManager.capture()
        let sig = signature(of: layout)
        guard sig != lastSignature else { return }
        lastSignature = sig
        onChange?(layout)
    }

    /// Only the things a saved layout actually restores.
    private func signature(of layout: NativeDockLayout) -> String {
        (layout.persistentApps + ["|"] + layout.persistentOthers).joined(separator: "\u{1F}")
    }
}
