import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Widget gallery

struct WidgetGalleryPane: View {
    @EnvironmentObject private var store: DocklyStore
    @EnvironmentObject private var selection: SettingsSelection
    @State private var query = ""

    private var targetID: UUID {
        selection.profileID ?? store.library.activeProfileID ?? store.library.profiles[0].id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: L("%d widgets. All included.", WidgetKind.allCases.count),
                       subtitle: L("Click a widget to add it to the selected setup."))

            HStack(spacing: 10) {
                TextField(L("Search widgets"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Spacer()
                Text(L("Adding to"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { targetID },
                    set: { selection.profileID = $0 })) {
                        ForEach(store.library.profiles) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(WidgetCategory.allCases) { cat in
                        let kinds = matches(in: cat)
                        if !kinds.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(cat.title)
                                    .font(.system(size: 13, weight: .bold))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)],
                                          spacing: 12) {
                                    ForEach(kinds) { kind in
                                        card(kind)
                                    }
                                }
                            }
                        }
                    }
                    Text(L("New widgets get added regularly."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
        }
    }

    private func matches(in cat: WidgetCategory) -> [WidgetKind] {
        WidgetKind.allCases.filter {
            $0.category == cat &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                           || $0.blurb.localizedCaseInsensitiveContains(query))
        }
    }

    /// How many of this widget the target setup already holds.
    private func count(of kind: WidgetKind) -> Int {
        store.profile(targetID)?.items
            .filter { $0.kind == .widget && $0.widget?.kind == kind }
            .count ?? 0
    }

    private func card(_ kind: WidgetKind) -> some View {
        let added = count(of: kind)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(added > 0 ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(kind.title).font(.system(size: 12, weight: .semibold))
                    if added > 0 {
                        Text(added == 1 ? L("Added") : L("Added ×%d", added))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    }
                }
                Text(kind.blurb)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                Button {
                    store.addItem(.widget(kind), to: targetID)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(L("Add to this setup"))

                if added > 0 {
                    Button {
                        removeLast(kind)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Remove the last one"))
                }
            }
            .font(.system(size: 14))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(added > 0 ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(added > 0 ? 0.45 : 0), lineWidth: 1)
        )
    }

    private func removeLast(_ kind: WidgetKind) {
        guard let profile = store.profile(targetID),
              let item = profile.items.last(where: {
                  $0.kind == .widget && $0.widget?.kind == kind
              })
        else { return }
        store.removeItem(item.id, from: targetID)
    }

}

// MARK: - Appearance

struct AppearancePane: View {
    @EnvironmentObject private var store: DocklyStore
    @EnvironmentObject private var selection: SettingsSelection

    private var profileID: UUID {
        selection.profileID ?? store.library.activeProfileID ?? store.library.profiles[0].id
    }
    private var appearance: DockAppearance {
        store.profile(profileID)?.appearance ?? DockAppearance()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: L("At home on your screen."),
                           subtitle: L("Where your Dock lives, how it looks, and when it hides."))
                    .padding(.horizontal, -22)

                HStack {
                    Text(L("Setup")).frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { profileID }, set: { selection.profileID = $0 })) {
                            ForEach(store.library.profiles) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 180)
                    Spacer()
                }

                SettingsCard(title: L("Position")) {
                    row("Edge") {
                        Picker("", selection: bind(\.edge)) {
                            ForEach(DockEdge.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 280)
                    }
                    row("Alignment") {
                        Picker("", selection: bind(\.alignment)) {
                            ForEach(DockAlignment.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 220)
                    }
                    row("Display") {
                        Picker("", selection: Binding(
                            get: { appearance.screenID ?? "" },
                            set: { setScreen($0) })) {
                                Text(L("Follow the pointer")).tag("")
                                Text(L("Every display")).tag(DockAppearance.everyScreen)
                                Divider()
                                ForEach(NSScreen.screens, id: \.docklyID) { s in
                                    Text(s.docklyName).tag(s.docklyID)
                                }
                            }
                            .labelsHidden().frame(width: 220)
                    }
                    row("Margin") {
                        slider(bind(\.screenMargin), 0...80, "\(Int(appearance.screenMargin)) pt")
                    }
                }

                SettingsCard(title: L("Size")) {
                    row("Icon size") {
                        slider(bind(\.iconSize), 28...84, "\(Int(appearance.iconSize)) pt")
                    }
                    row("Spacing") {
                        slider(bind(\.spacing), 0...24, "\(Int(appearance.spacing)) pt")
                    }
                    row("Padding") {
                        slider(bind(\.padding), 0...28, "\(Int(appearance.padding)) pt")
                    }
                    row("Corner radius") {
                        slider(bind(\.cornerRadius), 0...40, "\(Int(appearance.cornerRadius)) pt")
                    }
                }

                SettingsCard(title: L("Look")) {
                    row("Material") {
                        Picker("", selection: bind(\.material)) {
                            ForEach(DockMaterial.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 180)
                    }
                    row("Opacity") {
                        slider(bind(\.opacity), 0.3...1, "\(Int(appearance.opacity * 100))%")
                    }
                    Toggle(L("Magnify icons on hover"), isOn: bind(\.magnificationEnabled))
                    if appearance.magnificationEnabled {
                        row("Magnification") {
                            slider(bind(\.magnification), 1.05...2.0,
                                   String(format: "%.2f×", appearance.magnification))
                        }
                    }
                    Toggle(L("Show labels under icons"), isOn: bind(\.showLabels))
                }

                SettingsCard(title: L("Contents")) {
                    Toggle(L("Show running apps that are not in this dock"),
                           isOn: bind(\.showRunningApps))
                    Toggle(L("Keep a Trash tile at the end"), isOn: bind(\.showTrash))
                    Text(L("Folders open as a stack by default — right-click one in the dock to open it in Finder instead."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                SettingsCard(title: L("Behaviour")) {
                    row("Hiding") {
                        Picker("", selection: bind(\.hideMode)) {
                            ForEach(DockHideMode.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 220)
                    }
                    Toggle(L("Two-finger swipe switches setups"), isOn: bind(\.swipeToSwitch))
                    Divider()
                    Text(L("Which Dock you see is set under General → Dockly Mode."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            content()
            Spacer()
        }
    }

    private func slider(_ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ caption: String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range).frame(width: 220)
            Text(caption)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
        }
    }

    private func bind<V>(_ key: WritableKeyPath<DockAppearance, V>) -> Binding<V> {
        Binding(
            get: { appearance[keyPath: key] },
            set: { v in store.update(profileID) { $0.appearance[keyPath: key] = v } })
    }

    private func setScreen(_ id: String) {
        store.update(profileID) { $0.appearance.screenID = id.isEmpty ? nil : id }
    }
}

// MARK: - Focus

struct FocusPane: View {
    @EnvironmentObject private var store: DocklyStore
    @ObservedObject private var focus = FocusMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: L("A different setup for every part of your day."),
                           subtitle: L("Bind a setup to a macOS Focus and Dockly switches on its own."))
                    .padding(.horizontal, -22)

                Toggle(L("Follow macOS Focus modes"), isOn: Binding(
                    get: { store.library.settings.followFocusModes },
                    set: { store.library.settings.followFocusModes = $0 }))

                SettingsCard(title: L("Current Focus")) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill").foregroundStyle(.purple)
                        Text(focus.activeModeID.map { focus.name(for: $0) } ?? "None")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button(L("Refresh")) { focus.reloadModes() }
                    }
                }

                SettingsCard(title: L("Bindings")) {
                    ForEach(store.library.profiles) { p in
                        HStack(spacing: 10) {
                            Image(systemName: p.symbol).foregroundStyle(p.color).frame(width: 18)
                            Text(p.name).frame(width: 140, alignment: .leading)
                            FocusModePicker(profileID: p.id)
                            Spacer()
                        }
                    }
                }

                Text(L("Dockly reads the Focus state macOS already publishes on this Mac. Nothing leaves your machine."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject private var store: DocklyStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: L("General"),
                           subtitle: L("How Dockly behaves day to day."))
                    .padding(.horizontal, -22)

                SettingsCard(title: L("Dockly Mode")) {
                    Picker("", selection: Binding(
                        get: { store.library.settings.mode },
                        set: { store.library.settings.mode = $0
                               (NSApp.delegate as? AppDelegate)?.applySystemDockPreference()
                               DockPanelController.shared.refresh() })) {
                        ForEach(DockMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    Text(store.library.settings.mode.blurb)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(L("Dockly puts the macOS Dock back the way it found it when you quit."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                SettingsCard(title: L("Startup")) {
                    Toggle(L("Launch Dockly at login"), isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = $0; LaunchAtLogin.set($0)
                               store.library.settings.launchAtLogin = $0 }))
                    Toggle(L("Show the menu bar icon"), isOn: Binding(
                        get: { store.library.settings.showMenuBarIcon },
                        set: { store.library.settings.showMenuBarIcon = $0
                               MenuBarController.shared.refreshVisibility() }))
                    Toggle(L("Show the active setup's name in the menu bar"), isOn: Binding(
                        get: { store.library.settings.showMenuBarName },
                        set: { store.library.settings.showMenuBarName = $0 }))
                }

                SettingsCard(title: L("Switching")) {
                    HStack {
                        Text(L("Cycle setups")).frame(width: 150, alignment: .leading)
                        HotkeyField(hotkey: Binding(
                            get: { store.library.settings.cycleHotkey },
                            set: { store.library.settings.cycleHotkey = $0
                                   HotkeyCenter.shared.rebind(store: store) }))
                    }
                    Toggle(L("Show the setup name when switching"), isOn: Binding(
                        get: { store.library.settings.showSwitchOverlay },
                        set: { store.library.settings.showSwitchOverlay = $0 }))
                    Toggle(L("Haptic feedback on switch"), isOn: Binding(
                        get: { store.library.settings.hapticOnSwitch },
                        set: { store.library.settings.hapticOnSwitch = $0 }))
                }

                UpdatesCard()

                SettingsCard(title: L("macOS Dock")) {
                    Toggle(L("Save changes I make to the macOS Dock into the active setup"),
                           isOn: Binding(
                        get: { store.library.settings.saveNativeDockChanges },
                        set: { store.library.settings.saveNativeDockChanges = $0 }))
                    Text(L("Only applies to setups that restore a saved macOS Dock layout."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                SettingsCard(title: L("Permissions")) {
                    Toggle(L("Show notification badges on app icons"), isOn: Binding(
                        get: { store.library.settings.showAppBadges },
                        set: { store.library.settings.showAppBadges = $0
                               if $0 { BadgeReader.shared.start() }
                               else { BadgeReader.shared.stop() } }))
                    BadgeAccessRow()
                    permissionRow("Calendar", granted: EventKitSource.shared.calendarAuthorized) {
                        EventKitSource.shared.requestCalendarAccess()
                    }
                    permissionRow("Reminders", granted: EventKitSource.shared.remindersAuthorized) {
                        EventKitSource.shared.requestRemindersAccess()
                    }
                    HStack {
                        Text(L("Location (weather)")).frame(width: 170, alignment: .leading)
                        Button(L("Request")) { WeatherSource.shared.start() }
                        Spacer()
                    }
                    Button(L("Open System Settings → Privacy")) {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    private func permissionRow(_ name: String, granted: Bool,
                               request: @escaping () -> Void) -> some View {
        HStack {
            Text(name).frame(width: 170, alignment: .leading)
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            if !granted { Button(L("Allow"), action: request) }
            Spacer()
        }
    }
}

// MARK: - Backup

struct BackupPane: View {
    @EnvironmentObject private var store: DocklyStore
    @State private var status: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneHeader(title: L("Keep your setups."),
                           subtitle: L("Back them up, or move them to another Mac. No account needed."))
                    .padding(.horizontal, -22)

                SettingsCard(title: L("Transfer")) {
                    HStack(spacing: 10) {
                        Button(L("Export…")) { export() }
                        Button(L("Import and replace…")) { importLibrary(.replace) }
                        Button(L("Import and merge…")) { importLibrary(.merge) }
                        Spacer()
                    }
                    if let status {
                        Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(L("Everything lives in one JSON file. API keys stay in the Keychain and are never exported."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                SettingsCard(title: L("Automatic backups")) {
                    HStack {
                        Button(L("Back up now")) {
                            if let url = store.makeBackup() {
                                status = "Saved \(url.lastPathComponent)"
                            }
                        }
                        Button(L("Reveal in Finder")) {
                            NSWorkspace.shared.open(DocklyStore.backupsDirectory)
                        }
                        Spacer()
                    }
                    let list = store.backups()
                    if list.isEmpty {
                        Text(L("No backups yet.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        ForEach(list.prefix(8), id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button(L("Restore")) {
                                    if store.importLibrary(from: url, mode: .replace) {
                                        status = "Restored \(url.lastPathComponent)"
                                        HotkeyCenter.shared.rebind(store: store)
                                    }
                                }
                                .buttonStyle(.borderless).font(.system(size: 11))
                            }
                        }
                    }
                }

                SettingsCard(title: L("Where things live")) {
                    Text(DocklyStore.libraryURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Dockly Setups.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        status = store.exportLibrary(to: url) ? "Exported to \(url.lastPathComponent)"
                                              : "Export failed"
    }

    private func importLibrary(_ mode: DocklyStore.ImportMode) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.importLibrary(from: url, mode: mode) {
            HotkeyCenter.shared.rebind(store: store)
            status = mode == .replace ? "Replaced with \(url.lastPathComponent)"
                                      : "Merged \(url.lastPathComponent)"
        } else {
            status = "That file could not be read"
        }
    }
}

// MARK: - About

struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaneHeader(title: L("Dockly"),
                       subtitle: L("Custom docks and widgets for your Mac."))
                .padding(.horizontal, -22)

            Text(L("Your Dock. Reimagined."))
                .font(.system(size: 26, weight: .bold, design: .serif))

            Text(L("about-blurb"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

            SettingsCard(title: L("This build")) {
                Text(L("Version 1.0 · macOS 13 or later"))
                    .font(.system(size: 12))
                Text(L("Everything is stored locally. No account, no telemetry."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Badges need Accessibility access, so the row says plainly what is missing.
struct BadgeAccessRow: View {
    @ObservedObject private var reader = BadgeReader.shared

    var body: some View {
        HStack {
            Text(L("Accessibility (badges)")).frame(width: 170, alignment: .leading)
            Image(systemName: reader.isTrusted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(reader.isTrusted ? .green : .secondary)
            if !reader.isTrusted {
                Button(L("Allow")) { reader.requestAccess() }
                Button(L("Open Settings")) { reader.openAccessibilitySettings() }
                    .buttonStyle(.link)
            }
            Spacer()
        }
    }
}


/// General → Updates. Deliberately compact: one status line and one action.
struct UpdatesCard: View {
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var showFeedField = false

    var body: some View {
        SettingsCard(title: L("Updates")) {
            HStack(spacing: 10) {
                Text("Dockly \(updates.currentVersion) (\(updates.currentBuild))")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                action
            }
            HStack(spacing: 6) {
                if case .checking = updates.state {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                }
                Text(updates.state.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(isFailure ? .orange : .secondary)
            }
            if case .available(let release) = updates.state, let notes = release.notes {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(L("Check for updates automatically"), isOn: Binding(
                get: { updates.checksAutomatically },
                set: { updates.checksAutomatically = $0 }))
            DisclosureGroup(L("Update feed"), isExpanded: $showFeedField) {
                TextField(L("https://…/appcast.json"), text: Binding(
                    get: { updates.feedURL }, set: { updates.feedURL = $0 }))
                .frame(width: 320)
                .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }

    private var isFailure: Bool {
        if case .failed = updates.state { return true }
        return false
    }

    @ViewBuilder
    private var action: some View {
        switch updates.state {
        case .available(let release):
            Button("Download \(release.version)") { updates.download(release) }
        case .downloading:
            Button(L("Cancel")) { updates.cancel() }
        case .downloaded(let url):
            Button(L("Show in Finder")) { updates.revealDownload(url) }
        default:
            Button(L("Check now")) { updates.check(userInitiated: true) }
        }
    }
}
