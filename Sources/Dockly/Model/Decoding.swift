import Foundation

/// Reading a saved library must never fail because a newer Dockly added a
/// field. Swift's synthesised decoder throws on a missing key even when the
/// property has a default, which would silently reset everything the user
/// built — so the library's types decode key by key, falling back to the
/// default whenever a key is absent or the wrong shape.
struct AnyKey: CodingKey {
    var stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == AnyKey {
    func value<T: Decodable>(_ name: String, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: AnyKey(stringValue: name)))
            .flatMap { $0 } ?? fallback
    }

    func optional<T: Decodable>(_ name: String) -> T? {
        (try? decodeIfPresent(T.self, forKey: AnyKey(stringValue: name))) ?? nil
    }
}

// MARK: - DockItem

extension DockItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let fallback = DockItem(kind: .spacer)
        self.init(
            id: c.value("id", UUID()),
            kind: c.value("kind", DockItemKind.spacer),
            title: c.value("title", ""),
            path: c.optional("path"),
            bookmark: c.optional("bookmark"),
            link: c.optional("link"),
            shortcutName: c.optional("shortcutName"),
            tint: c.optional("tint"),
            letter: c.optional("letter"),
            symbol: c.optional("symbol"),
            widget: c.optional("widget"),
            spacerWidth: c.value("spacerWidth", fallback.spacerWidth),
            folderAction: c.value("folderAction", FolderAction.stack),
            bundleID: c.optional("bundleID"))
    }
}

// MARK: - WidgetInstance

extension WidgetInstance {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(kind: c.value("kind", WidgetKind.clock),
                  settings: c.value("settings", [String: String]()))
    }
}

// MARK: - DockAppearance

extension DockAppearance {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let d = DockAppearance()
        self.init(
            edge: c.value("edge", d.edge),
            alignment: c.value("alignment", d.alignment),
            iconSize: c.value("iconSize", d.iconSize),
            magnification: c.value("magnification", d.magnification),
            magnificationEnabled: c.value("magnificationEnabled", d.magnificationEnabled),
            spacing: c.value("spacing", d.spacing),
            padding: c.value("padding", d.padding),
            cornerRadius: c.value("cornerRadius", d.cornerRadius),
            opacity: c.value("opacity", d.opacity),
            material: c.value("material", d.material),
            screenMargin: c.value("screenMargin", d.screenMargin),
            hideMode: c.value("hideMode", d.hideMode),
            showLabels: c.value("showLabels", d.showLabels),
            screenID: c.optional("screenID"),
            swipeToSwitch: c.value("swipeToSwitch", d.swipeToSwitch),
            showRunningApps: c.value("showRunningApps", d.showRunningApps),
            showTrash: c.value("showTrash", d.showTrash))
    }
}

// MARK: - DockProfile

extension DockProfile {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let d = DockProfile()
        self.init(
            id: c.value("id", UUID()),
            name: c.value("name", d.name),
            symbol: c.value("symbol", d.symbol),
            accent: c.value("accent", d.accent),
            items: c.value("items", [DockItem]()),
            appearance: c.value("appearance", DockAppearance()),
            hotkey: c.optional("hotkey"),
            focusModeID: c.optional("focusModeID"),
            nativeDock: c.optional("nativeDock"),
            appliesNativeDock: c.value("appliesNativeDock", d.appliesNativeDock),
            customDockEnabled: c.value("customDockEnabled", d.customDockEnabled))
    }
}

// MARK: - NativeDockLayout

extension NativeDockLayout {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(
            persistentApps: c.value("persistentApps", [String]()),
            persistentOthers: c.value("persistentOthers", [String]()),
            tileSize: c.optional("tileSize"),
            magnification: c.optional("magnification"),
            largeSize: c.optional("largeSize"),
            orientation: c.optional("orientation"),
            autohide: c.optional("autohide"),
            capturedAt: c.value("capturedAt", Date()))
    }
}

// MARK: - GlobalSettings

extension GlobalSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let d = GlobalSettings()
        self.init(
            mode: c.value("mode", d.mode),
            showMenuBarName: c.value("showMenuBarName", d.showMenuBarName),
            saveNativeDockChanges: c.value("saveNativeDockChanges", d.saveNativeDockChanges),
            showAppBadges: c.value("showAppBadges", d.showAppBadges),
            launchAtLogin: c.value("launchAtLogin", d.launchAtLogin),
            hideSystemDock: c.value("hideSystemDock", d.hideSystemDock),
            systemDockAutohideWas: c.optional("systemDockAutohideWas"),
            showMenuBarIcon: c.value("showMenuBarIcon", d.showMenuBarIcon),
            cycleHotkey: c.optional("cycleHotkey"),
            followFocusModes: c.value("followFocusModes", d.followFocusModes),
            hapticOnSwitch: c.value("hapticOnSwitch", d.hapticOnSwitch),
            showSwitchOverlay: c.value("showSwitchOverlay", d.showSwitchOverlay))
    }
}

// MARK: - DockLibrary

extension DockLibrary {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        self.init(
            version: c.value("version", 1),
            profiles: c.value("profiles", [DockProfile]()),
            activeProfileID: c.optional("activeProfileID"),
            settings: c.value("settings", GlobalSettings()))
    }
}
