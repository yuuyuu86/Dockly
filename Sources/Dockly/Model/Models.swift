import Foundation
import SwiftUI

// MARK: - Dock item

enum DockItemKind: String, Codable, CaseIterable {
    case app, folder, file, url, shortcut, spacer, divider, widget, trash
}

/// What a folder tile does when you click it.
enum FolderAction: String, Codable, CaseIterable, Identifiable {
    case stack, openInFinder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stack:        return L("Show contents")
        case .openInFinder: return L("Open in Finder")
        }
    }
}

/// One thing that lives in a Dockly dock: an app, a file, a folder, a link,
/// a macOS Shortcut, a bit of empty space, or a widget.
struct DockItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: DockItemKind
    var title: String = ""
    /// Resolved path for app/folder/file items.
    var path: String?
    /// Security-scoped bookmark so access survives relaunches.
    var bookmark: Data?
    /// Destination for `.url` items.
    var link: String?
    /// Name of the macOS Shortcut to run.
    var shortcutName: String?
    /// Folder/file tint, as a hex string.
    var tint: String?
    /// A single character stamped on a folder so it is easy to spot.
    var letter: String?
    /// SF Symbol used when there is no natural icon.
    var symbol: String?
    /// Widget payload for `.widget` items.
    var widget: WidgetInstance?
    /// Width of a `.spacer`, in points.
    var spacerWidth: Double = 16
    /// What a `.folder` tile does when clicked.
    var folderAction: FolderAction = .stack
    /// Bundle identifier for `.app` items, used to find the app again if it
    /// moves or is reinstalled somewhere else.
    var bundleID: String?

    static func app(path: String) -> DockItem {
        var item = DockItem(kind: .app, title: (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".app", with: ""), path: path)
        item.bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        return item
    }

    static func widget(_ kind: WidgetKind) -> DockItem {
        DockItem(kind: .widget, title: kind.title, widget: WidgetInstance(kind: kind))
    }

    var fileURL: URL? {
        if let path { return URL(fileURLWithPath: path) }
        return nil
    }
}

// MARK: - Widgets

struct WidgetInstance: Codable, Hashable {
    var kind: WidgetKind
    /// Free-form per-widget configuration, kept as strings so the whole
    /// library stays a plain, portable JSON document.
    var settings: [String: String] = [:]

    subscript(key: String) -> String? {
        get { settings[key] }
        set { settings[key] = newValue }
    }

    func string(_ key: String, _ fallback: String = "") -> String {
        settings[key] ?? fallback
    }
    func int(_ key: String, _ fallback: Int) -> Int {
        settings[key].flatMap(Int.init) ?? fallback
    }
    func double(_ key: String, _ fallback: Double) -> Double {
        settings[key].flatMap(Double.init) ?? fallback
    }
    func bool(_ key: String, _ fallback: Bool) -> Bool {
        settings[key].map { $0 == "true" } ?? fallback
    }
}

// MARK: - Appearance

enum DockEdge: String, Codable, CaseIterable, Identifiable {
    case bottom, top, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottom: return L("Bottom")
        case .top: return L("Top")
        case .left: return L("Left")
        case .right: return L("Right")
        }
    }
    var isVertical: Bool { self == .left || self == .right }
}

enum DockAlignment: String, Codable, CaseIterable, Identifiable {
    case start, center, end
    var id: String { rawValue }
    var title: String {
        switch self {
        case .start: return L("Start")
        case .center: return L("Center")
        case .end: return L("End")
        }
    }
}

enum DockHideMode: String, Codable, CaseIterable, Identifiable {
    case never, auto, whenFullScreen
    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: return L("Always visible")
        case .auto: return L("Hide automatically")
        case .whenFullScreen: return L("Hide in full screen")
        }
    }
}

enum DockMaterial: String, Codable, CaseIterable, Identifiable {
    case regular, thick, thin, ultraThin, solid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: return L("Regular")
        case .thick: return L("Thick")
        case .thin: return L("Thin")
        case .ultraThin: return L("Ultra thin")
        case .solid: return L("Solid")
        }
    }
}

struct DockAppearance: Codable, Hashable {
    /// Sentinel for `screenID` meaning "one dock per display".
    static let everyScreen = "all-screens"

    var edge: DockEdge = .bottom
    var alignment: DockAlignment = .center
    var iconSize: Double = 48
    var magnification: Double = 1.35
    var magnificationEnabled: Bool = true
    var spacing: Double = 8
    var padding: Double = 10
    var cornerRadius: Double = 22
    var opacity: Double = 1.0
    var material: DockMaterial = .regular
    var screenMargin: Double = 12
    var hideMode: DockHideMode = .auto
    var showLabels: Bool = false
    /// nil follows the screen with the mouse; `DockAppearance.everyScreen`
    /// puts a dock on each display; anything else pins it to that display.
    var screenID: String?
    var swipeToSwitch: Bool = true
    /// Append tiles for running apps that are not already in the dock.
    var showRunningApps: Bool = false
    /// Keep a Trash tile at the end, the way the system Dock does.
    var showTrash: Bool = false
}

// MARK: - Hotkey

struct Hotkey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32       // Carbon modifier mask

    var display: String {
        var out = ""
        if modifiers & UInt32(1 << 12) != 0 { out += "⌃" }   // controlKey
        if modifiers & UInt32(1 << 11) != 0 { out += "⌥" }   // optionKey
        if modifiers & UInt32(1 << 9)  != 0 { out += "⇧" }   // shiftKey
        if modifiers & UInt32(1 << 8)  != 0 { out += "⌘" }   // cmdKey
        out += KeyCodeNames.name(for: keyCode)
        return out
    }
}

// MARK: - macOS Dock layout

/// A snapshot of the *system* Dock so Dockly can put your familiar Dock back
/// exactly how it was.
struct NativeDockLayout: Codable, Hashable {
    var persistentApps: [String] = []      // file paths
    var persistentOthers: [String] = []    // folders / stacks
    var tileSize: Double?
    var magnification: Bool?
    var largeSize: Double?
    var orientation: String?
    var autohide: Bool?
    var capturedAt: Date = Date()

    var isEmpty: Bool { persistentApps.isEmpty && persistentOthers.isEmpty }
}

// MARK: - Profile

struct DockProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Setup"
    var symbol: String = "square.stack.3d.up"
    var accent: String = "#5B8CFF"
    var items: [DockItem] = []
    var appearance: DockAppearance = DockAppearance()
    var hotkey: Hotkey?
    /// Identifier of the macOS Focus mode that activates this setup.
    var focusModeID: String?
    /// The system Dock layout to restore alongside this setup.
    var nativeDock: NativeDockLayout?
    var appliesNativeDock: Bool = false
    var customDockEnabled: Bool = true

    var color: Color { Color(hex: accent) ?? .accentColor }
}

// MARK: - Global settings

/// Which Dock (or Docks) you actually want on screen.
enum DockMode: String, Codable, CaseIterable, Identifiable {
    case macOSDock, custom, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .macOSDock: return L("macOS Dock")
        case .custom:    return L("Custom docks")
        case .both:      return L("Both")
        }
    }
    var blurb: String {
        switch self {
        case .macOSDock: return L("Setups swap your familiar Dock. Dockly stays out of sight.")
        case .custom:    return L("Dockly replaces the Dock and keeps the system one hidden.")
        case .both:      return L("Dockly sits alongside the Dock you already have.")
        }
    }
    var showsCustomDock: Bool { self != .macOSDock }
    var hidesSystemDock: Bool { self == .custom }
}

struct GlobalSettings: Codable, Hashable {
    var mode: DockMode = .custom
    /// Show the active setup's name next to the menu bar icon.
    var showMenuBarName: Bool = false
    /// Keep a setup's saved macOS Dock in step with changes you make by hand.
    var saveNativeDockChanges: Bool = false
    /// Draw the notification badges macOS puts on Dock tiles (needs
    /// Accessibility access).
    var showAppBadges: Bool = true
    var launchAtLogin: Bool = false
    /// Tuck the system Dock away while Dockly is running.
    var hideSystemDock: Bool = true
    /// What the system Dock's autohide was before Dockly touched it, so
    /// quitting can put it back.
    var systemDockAutohideWas: Bool?
    var showMenuBarIcon: Bool = true
    var cycleHotkey: Hotkey? = Hotkey(keyCode: 48, modifiers: UInt32(1 << 11) | UInt32(1 << 12)) // ⌃⌥Tab
    var followFocusModes: Bool = true
    var hapticOnSwitch: Bool = true
    var showSwitchOverlay: Bool = true
}

// MARK: - Library (the whole document)

struct DockLibrary: Codable {
    var version: Int = 1
    var profiles: [DockProfile] = []
    var activeProfileID: UUID?
    var settings: GlobalSettings = GlobalSettings()

    var activeProfile: DockProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }
}
