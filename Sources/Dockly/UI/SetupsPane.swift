import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SetupsPane: View {
    @EnvironmentObject private var store: DocklyStore
    @EnvironmentObject private var selection: SettingsSelection
    @State private var recordingHotkey = false

    private var profile: DockProfile? {
        store.library.profiles.first { $0.id == selection.profileID }
            ?? store.library.profiles.first
    }

    var body: some View {
        HStack(spacing: 0) {
            profileList
            Divider()
            if let profile {
                profileEditor(profile)
            } else {
                Text(L("No setups")).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Profile list

    private var profileList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { selection.profileID },
                set: { selection.profileID = $0 })
            ) {
                ForEach(store.library.profiles) { p in
                    HStack(spacing: 8) {
                        Image(systemName: p.symbol)
                            .foregroundStyle(p.color)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.system(size: 12, weight: .medium))
                            Text(L("%d items", p.items.count))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.library.activeProfileID == p.id {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                        }
                    }
                    .tag(p.id)
                    .contextMenu {
                        Button(L("Activate")) { store.activate(p.id) }
                        Button(L("Duplicate")) { store.duplicate(p.id) }
                        Divider()
                        Button(L("Delete"), role: .destructive) { store.confirmDelete(p.id) }
                    }
                }
                .onMove { from, to in
                    store.library.profiles.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 6) {
                Button {
                    let p = store.addProfile()
                    selection.profileID = p.id
                } label: { Image(systemName: "plus") }
                Button {
                    if let id = selection.profileID, store.confirmDelete(id) {
                        selection.profileID = store.library.profiles.first?.id
                    }
                } label: { Image(systemName: "minus") }
                .disabled(store.library.profiles.count <= 1)
                Spacer()
                Button(L("Activate")) {
                    if let id = selection.profileID { store.activate(id) }
                }
                .disabled(selection.profileID == store.library.activeProfileID)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .frame(width: 210)
    }

    // MARK: Editor

    private func profileEditor(_ p: DockProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                identityCard(p)
                itemsCard(p)
                switchingCard(p)
                nativeDockCard(p)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
        }
    }

    private func identityCard(_ p: DockProfile) -> some View {
        SettingsCard(title: L("Setup")) {
            HStack(spacing: 12) {
                TextField(L("Name"), text: binding(p, \.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Picker("", selection: binding(p, \.symbol)) {
                    ForEach(Self.symbols, id: \.self) { s in
                        Image(systemName: s).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 70)

                ForEach(Color.docklyPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(p.accent == hex ? 0.9 : 0),
                                                  lineWidth: 2)
                        )
                        .onTapGesture { store.update(p.id) { $0.accent = hex } }
                }
                Spacer()
            }
            Toggle(L("Show a custom Dock for this setup"), isOn: binding(p, \.customDockEnabled))
        }
    }

    // MARK: Items

    private func itemsCard(_ p: DockProfile) -> some View {
        SettingsCard(title: L("Dock items")) {
            HStack(spacing: 8) {
                Menu(L("Add")) {
                    Button(L("App…")) { addApp(p) }
                    Button(L("Folder…")) { addFolder(p) }
                    Button(L("File…")) { addFile(p) }
                    Button(L("Link…")) { addLink(p) }
                    Divider()
                    Menu(L("Shortcut")) {
                        if ShortcutsRunner.shared.names.isEmpty {
                            Button(L("Load Shortcuts…")) { ShortcutsRunner.shared.reload() }
                        }
                        ForEach(ShortcutsRunner.shared.names.prefix(40), id: \.self) { n in
                            Button(n) {
                                store.addItem(DockItem(kind: .shortcut, title: n,
                                                       shortcutName: n), to: p.id)
                            }
                        }
                    }
                    Menu(L("Widget")) {
                        ForEach(WidgetCategory.allCases) { cat in
                            Menu(cat.title) {
                                ForEach(WidgetKind.allCases.filter { $0.category == cat }) { k in
                                    Button(k.title) { store.addItem(.widget(k), to: p.id) }
                                }
                            }
                        }
                    }
                    Divider()
                    Button(L("Small spacer")) {
                        store.addItem(DockItem(kind: .spacer, spacerWidth: 8), to: p.id)
                    }
                    Button(L("Spacer")) {
                        store.addItem(DockItem(kind: .spacer, spacerWidth: 24), to: p.id)
                    }
                    Button(L("Divider")) { store.addItem(DockItem(kind: .divider), to: p.id) }
                    Divider()
                    Button(L("Trash")) { store.addItem(DockItem(kind: .trash, title: "Trash"), to: p.id) }
                }
                .frame(width: 90)

                Text(L("Drag to reorder. Drop files onto the dock itself to add them."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }

            if p.items.isEmpty {
                Text(L("Nothing here yet."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(p.items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item, profile: p, index: index)
                        if index < p.items.count - 1 { Divider().opacity(0.4) }
                    }
                }
            }
        }
    }

    // MARK: Switching

    private func switchingCard(_ p: DockProfile) -> some View {
        SettingsCard(title: L("Switching")) {
            HStack(spacing: 10) {
                Text(L("Keyboard shortcut")).frame(width: 150, alignment: .leading)
                HotkeyField(hotkey: Binding(
                    get: { p.hotkey },
                    set: { new in
                        store.update(p.id) { $0.hotkey = new }
                        HotkeyCenter.shared.rebind(store: store)
                    }))
            }
            HStack(spacing: 10) {
                Text(L("Activate with Focus")).frame(width: 150, alignment: .leading)
                FocusModePicker(profileID: p.id)
                Spacer()
            }
        }
    }

    // MARK: macOS Dock

    private func nativeDockCard(_ p: DockProfile) -> some View {
        SettingsCard(title: L("macOS Dock")) {
            Toggle(L("Also restore a saved macOS Dock layout"), isOn: binding(p, \.appliesNativeDock))
            HStack(spacing: 10) {
                Button(L("Save my current macOS Dock")) {
                    store.update(p.id) { $0.nativeDock = NativeDockManager.capture() }
                }
                if let layout = p.nativeDock, !layout.isEmpty {
                    Text(L("%1$d apps · saved %2$@", layout.persistentApps.count,
                         layout.capturedAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button(L("Apply now")) { NativeDockManager.apply(layout) }
                } else {
                    Text(L("Nothing saved yet."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Helpers

    private func binding<V>(_ p: DockProfile, _ key: WritableKeyPath<DockProfile, V>) -> Binding<V> {
        Binding(
            get: { store.profile(p.id)?[keyPath: key] ?? p[keyPath: key] },
            set: { new in store.update(p.id) { $0[keyPath: key] = new } })
    }

    private func addApp(_ p: DockProfile) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addItem(DockItem.make(from: url), to: p.id) }
    }

    private func addFolder(_ p: DockProfile) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addItem(DockItem.make(from: url), to: p.id) }
    }

    private func addFile(_ p: DockProfile) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addItem(DockItem.make(from: url), to: p.id) }
    }

    private func addLink(_ p: DockProfile) {
        let alert = NSAlert()
        alert.messageText = L("Add a link")
        alert.informativeText = L("Dockly will open this in your default browser.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = L("https://example.com")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Add"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        let raw = field.stringValue
        let host = URL(string: raw.contains("://") ? raw : "https://\(raw)")?.host ?? raw
        store.addItem(DockItem(kind: .url, title: host, link: raw,
                               tint: Color.docklyPalette.randomElement()), to: p.id)
    }

    static let symbols = [
        "square.stack.3d.up", "briefcase.fill", "house.fill", "moon.fill",
        "gamecontroller.fill", "paintbrush.fill", "terminal.fill", "book.fill",
        "airplane", "music.note", "camera.fill", "leaf.fill", "bolt.fill",
    ]
}

// MARK: - One row in the items list

private struct ItemRow: View {
    var item: DockItem
    var profile: DockProfile
    var index: Int
    @EnvironmentObject private var store: DocklyStore
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle).font(.system(size: 12, weight: .medium))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if hasSettings {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "slider.horizontal.3")
                    }
                    .buttonStyle(.borderless)
                }
                Button { move(-1) } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless).disabled(index >= profile.items.count - 1)
                Button(role: .destructive) {
                    store.removeItem(item.id, from: profile.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            .padding(.vertical, 6)

            if expanded {
                ItemSettingsEditor(item: item, profileID: profile.id)
                    .padding(.leading, 32)
                    .padding(.bottom, 10)
            }
        }
    }

    private var hasSettings: Bool {
        item.kind == .widget || item.kind == .folder || item.kind == .url
            || item.kind == .spacer || item.kind == .shortcut
    }

    private var displayTitle: String {
        switch item.kind {
        case .widget:  return item.widget?.kind.title ?? "Widget"
        case .spacer:  return L("Spacer")
        case .divider: return L("Divider")
        case .trash:   return L("Trash")
        default:       return item.title
        }
    }

    private var subtitle: String {
        switch item.kind {
        case .widget: return item.widget?.kind.category.title ?? ""
        case .url:    return item.link ?? ""
        case .shortcut: return L("Shortcut")
        case .trash:  return L("Trash")
        case .spacer: return "\(Int(item.spacerWidth)) pt"
        case .divider: return L("Separator")
        default:      return item.path ?? ""
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .widget:
            Image(systemName: item.widget?.kind.symbol ?? "square")
                .foregroundStyle(profile.color)
        case .app, .file, .folder:
            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: IconProvider.shared.icon(forPath: path, side: 44))
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
            }
        case .url:      Image(systemName: "globe").foregroundStyle(.blue)
        case .shortcut: Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.purple)
        case .trash:    Image(systemName: "trash").foregroundStyle(.secondary)
        case .spacer:   Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
        case .divider:  Image(systemName: "line.diagonal").foregroundStyle(.secondary)
        }
    }

    private func move(_ delta: Int) {
        store.moveItem(in: profile.id, from: index, to: index + delta)
    }
}
