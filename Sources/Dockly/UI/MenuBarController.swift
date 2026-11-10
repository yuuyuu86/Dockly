import AppKit
import SwiftUI
import Combine

/// The menu bar item: switch setups, toggle the dock, reach settings.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let store = DocklyStore.shared
    private var cancellables = Set<AnyCancellable>()

    func start() {
        refreshVisibility()
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateButton() }
            .store(in: &cancellables)
    }

    func refreshVisibility() {
        if store.library.settings.showMenuBarIcon {
            guard statusItem == nil else { updateButton(); return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = buildMenu()
            item.menu?.delegate = self
            statusItem = item
            updateButton()
        } else {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
        }
    }

    private func updateButton() {
        guard let button = statusItem?.button else { return }
        let profile = store.activeProfile
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = NSImage(systemSymbolName: profile.symbol,
                               accessibilityDescription: "Dockly")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true
        button.title = store.library.settings.showMenuBarName ? " \(profile.name)" : ""
        button.imagePosition = store.library.settings.showMenuBarName
            ? .imageLeading : .imageOnly
        button.toolTip = "Dockly — \(profile.name)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        populate(menu)
        return menu
    }

    private func populate(_ menu: NSMenu) {
        let header = NSMenuItem(title: L("Setups"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (i, p) in store.library.profiles.enumerated() {
            let item = NSMenuItem(title: p.name,
                                  action: #selector(selectProfile(_:)),
                                  keyEquivalent: i < 9 ? String(i + 1) : "")
            item.keyEquivalentModifierMask = [.command, .control]
            item.target = self
            item.representedObject = p.id
            item.state = p.id == store.library.activeProfileID ? .on : .off
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            item.image = NSImage(systemSymbolName: p.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            if let hk = p.hotkey {
                item.toolTip = "Shortcut: \(hk.display)"
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: store.activeProfile.customDockEnabled
                                    ? "Hide Dockly Dock" : "Show Dockly Dock",
                                action: #selector(toggleDock), keyEquivalent: "d")
        toggle.keyEquivalentModifierMask = [.command, .control]
        toggle.target = self
        menu.addItem(toggle)

        let next = NSMenuItem(title: L("Next Setup"), action: #selector(nextProfile),
                              keyEquivalent: "")
        next.target = self
        menu.addItem(next)

        let reveal = NSMenuItem(title: L("Show Dockly Now"), action: #selector(revealDock),
                                keyEquivalent: "s")
        reveal.keyEquivalentModifierMask = [.command, .control]
        reveal.target = self
        menu.addItem(reveal)

        let autoHide = NSMenuItem(title: L("Hide Dockly Automatically"),
                                  action: #selector(toggleAutoHide), keyEquivalent: "")
        autoHide.target = self
        autoHide.state = store.activeProfile.appearance.hideMode == .auto ? .on : .off
        menu.addItem(autoHide)

        menu.addItem(.separator())

        let macDock = NSMenu()
        let capture = NSMenuItem(title: L("Save current macOS Dock to this setup"),
                                 action: #selector(captureNativeDock), keyEquivalent: "")
        capture.target = self
        macDock.addItem(capture)
        let hideDock = NSMenuItem(title: L("Keep the macOS Dock Hidden"),
                                  action: #selector(toggleSystemDock), keyEquivalent: "")
        hideDock.target = self
        hideDock.state = store.library.settings.hideSystemDock ? .on : .off
        macDock.addItem(hideDock)
        let saveChanges = NSMenuItem(title: L("Save Changes I Make to the macOS Dock"),
                                     action: #selector(toggleSaveNativeChanges),
                                     keyEquivalent: "")
        saveChanges.target = self
        saveChanges.state = store.library.settings.saveNativeDockChanges ? .on : .off
        macDock.addItem(saveChanges)

        let macDockItem = NSMenuItem(title: L("macOS Dock"), action: nil, keyEquivalent: "")
        macDockItem.submenu = macDock
        menu.addItem(macDockItem)

        let modeMenu = NSMenu()
        for mode in DockMode.allCases {
            let m = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)),
                               keyEquivalent: "")
            m.target = self
            m.representedObject = mode.rawValue
            m.state = store.library.settings.mode == mode ? .on : .off
            m.toolTip = mode.blurb
            modeMenu.addItem(m)
        }
        let modeItem = NSMenuItem(title: L("Dockly Mode"), action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        if case .available(let release) = UpdateChecker.shared.state {
            let update = NSMenuItem(title: "Update to \(release.version)…",
                                    action: #selector(openUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: L("Dockly Settings…"), action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let widgets = NSMenuItem(title: L("Widget Library…"), action: #selector(openWidgets),
                                 keyEquivalent: "")
        widgets.target = self
        menu.addItem(widgets)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit Dockly"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        store.activate(id)
    }

    @objc private func toggleDock() {
        let id = store.activeProfile.id
        store.update(id) { $0.customDockEnabled.toggle() }
    }

    @objc private func nextProfile() { store.cycle(by: 1) }

    @objc private func captureNativeDock() {
        let id = store.activeProfile.id
        store.update(id) {
            $0.nativeDock = NativeDockManager.capture()
            $0.appliesNativeDock = true
        }
    }

    @objc private func revealDock() {
        let id = store.activeProfile.id
        // "Show it" has to mean show it, even if the setup had been switched off.
        if store.activeProfile.customDockEnabled == false {
            store.update(id) { $0.customDockEnabled = true }
            DockPanelController.shared.refresh()
        }
        if store.library.settings.mode == .macOSDock {
            store.library.settings.mode = .both
            (NSApp.delegate as? AppDelegate)?.applySystemDockPreference()
            DockPanelController.shared.refresh()
        }
        DockPanelController.shared.reveal()
    }

    @objc private func toggleAutoHide() {
        let id = store.activeProfile.id
        store.update(id) {
            $0.appearance.hideMode = $0.appearance.hideMode == .auto ? .never : .auto
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DockMode(rawValue: raw) else { return }
        store.library.settings.mode = mode
        (NSApp.delegate as? AppDelegate)?.applySystemDockPreference()
        DockPanelController.shared.refresh()
    }

    @objc private func toggleSaveNativeChanges() {
        store.library.settings.saveNativeDockChanges.toggle()
    }

    @objc private func toggleSystemDock() {
        let settings = store.library.settings
        store.library.settings.mode = settings.mode == .custom ? .both : .custom
        (NSApp.delegate as? AppDelegate)?.applySystemDockPreference()
        DockPanelController.shared.refresh()
    }

    @objc private func openSettings() { SettingsWindowController.shared.show(tab: .setups) }
    @objc private func openWidgets() { SettingsWindowController.shared.show(tab: .widgets) }
    @objc private func openUpdates() { SettingsWindowController.shared.show(tab: .general) }

    @objc private func quit() {
        store.saveNow()
        NSApp.terminate(nil)
    }
}
