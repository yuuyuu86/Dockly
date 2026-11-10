import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One position in the dock: an icon tile, a widget, a spacer or a divider.
struct DockSlotView: View {
    var item: DockItem
    var index: Int
    var profile: DockProfile
    @Binding var hoveredIndex: Int?
    @Binding var hoveredMagnifies: Bool
    @Binding var dropIndex: Int?

    @EnvironmentObject private var store: DocklyStore
    @ObservedObject private var badges = BadgeReader.shared
    @ObservedObject private var running = RunningAppsMonitor.shared
    @ObservedObject private var trash = TrashService.shared
    @State private var pressed = false
    @State private var dropTargeted = false
    /// Where this tile sits on screen, so a stack can open next to it.
    @State private var screenRect: CGRect = .zero

    private var a: DockAppearance { profile.appearance }
    private var side: CGFloat { CGFloat(a.iconSize) }

    /// Only icon tiles take part in magnification. Widgets are wide, so
    /// scaling them pushes their content over their neighbours instead of
    /// reading as a lift — and a widget is already legible at rest.
    private var magnifies: Bool {
        switch item.kind {
        case .app, .file, .folder, .url, .shortcut, .trash: return true
        case .spacer, .divider, .widget:                    return false
        }
    }

    /// Icons closest to the pointer grow the most, the way the system Dock
    /// does. The falloff only counts neighbouring tiles that magnify, so a
    /// widget sitting between two apps does not swallow the effect.
    private var magnification: CGFloat {
        guard magnifies, a.magnificationEnabled, hoveredMagnifies,
              let h = hoveredIndex else { return 1 }
        let distance = abs(index - h)
        let peak = CGFloat(a.magnification)
        switch distance {
        case 0:  return peak
        case 1:  return 1 + (peak - 1) * 0.45
        case 2:  return 1 + (peak - 1) * 0.15
        default: return 1
        }
    }

    var body: some View {
        content
            .scaleEffect(magnification * (pressed ? 0.9 : 1),
                         anchor: magnificationAnchor)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: magnification)
            .animation(.easeOut(duration: 0.09), value: pressed)
            .onHover { inside in
                if inside {
                    hoveredIndex = index
                    hoveredMagnifies = magnifies
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                    hoveredMagnifies = false
                }
            }
            .overlay(alignment: .topTrailing) { badge }
            .overlay(alignment: .bottom) { runningDot }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityName)
            .accessibilityHint(accessibilityHint)
            .contextMenu { menu }
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { captureRect(geo) }
                        .onChange(of: geo.frame(in: .global)) { _ in captureRect(geo) }
                }
            )
            .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
            .onDrop(of: [UTType.text.identifier, UTType.fileURL.identifier],
                    delegate: SlotDropDelegate(index: index, profileID: profile.id, store: store))
    }

    // MARK: Accessibility

    private var accessibilityName: String {
        switch item.kind {
        case .widget:  return item.widget?.kind.title ?? L("Widget")
        case .trash:   return trash.isEmpty ? L("Trash") : L("Trash — %d items", trash.itemCount)
        case .spacer:  return L("Spacer")
        case .divider: return L("Separator")
        default:
            guard let path = item.path, running.isRunning(path) else { return item.title }
            return L("%@, running", item.title)
        }
    }

    private var accessibilityHint: String {
        switch item.kind {
        case .app:      return L("Opens the app")
        case .folder:   return item.folderAction == .stack ? L("Shows the folder's contents")
                                                           : L("Opens the folder in Finder")
        case .file:     return L("Opens the file")
        case .url:      return L("Opens the link")
        case .shortcut: return L("Runs the Shortcut")
        case .trash:    return L("Opens the Trash")
        default:        return ""
        }
    }

    private var magnificationAnchor: UnitPoint {
        switch a.edge {
        case .bottom: return .bottom
        case .top:    return .top
        case .left:   return .leading
        case .right:  return .trailing
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .spacer:
            Color.clear.frame(width: a.edge.isVertical ? side : CGFloat(item.spacerWidth),
                              height: a.edge.isVertical ? CGFloat(item.spacerWidth) : side)
        case .divider:
            dividerView
        case .trash:
            trashTile
        case .widget:
            // Widgets size themselves to their contents: a reserved minimum
            // either leaves a gap beside a narrow widget or squeezes a wide
            // one, depending on which way the layout is measured.
            DockWidgetView(context: WidgetContext(
                item: item, profileID: profile.id,
                height: side, accent: profile.color))
            .frame(height: side)
        default:
            iconTile
        }
    }

    // MARK: Trash

    private var trashTile: some View {
        VStack(spacing: 2) {
            ZStack {
                Image(nsImage: trash.icon)
                    .resizable().scaledToFit()
                    .frame(width: side, height: side)
                if dropTargeted {
                    RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                        .fill(profile.color.opacity(0.28))
                        .frame(width: side, height: side)
                }
            }
            if a.showLabels {
                Text(trash.isEmpty ? L("Trash") : L("Trash (%d)", trash.itemCount))
                    .font(.system(size: max(7, side * 0.18), weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .frame(width: side * 1.4)
            }
        }
        .scaleEffect(dropTargeted ? 1.12 : 1)
        .animation(.spring(response: 0.22), value: dropTargeted)
        .contentShape(Rectangle())
        .onTapGesture { trash.open() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            collectURLs(providers) { urls in trash.moveToTrash(urls) }
            return true
        }
        .help(trash.isEmpty ? L("Trash") : L("Trash — %d items", trash.itemCount))
    }

    /// Remembers where the tile is in screen coordinates so a stack panel can
    /// be anchored to it.
    private func captureRect(_ geo: GeometryProxy) {
        let local = geo.frame(in: .global)
        guard let window = NSApp.windows.first(where: { $0 is DockPanel && $0.isVisible })
        else { return }
        let wf = window.frame
        // SwiftUI's global space is top-left based within the window.
        let rect = CGRect(x: wf.minX + local.minX,
                          y: wf.maxY - local.maxY,
                          width: local.width, height: local.height)
        if rect != screenRect { screenRect = rect }
    }

    private func collectURLs(_ providers: [NSItemProvider],
                             done: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }

    private var dividerView: some View {
        Group {
            if a.edge.isVertical {
                Rectangle().fill(Color.white.opacity(0.18))
                    .frame(width: side * 0.7, height: 1)
            } else {
                Rectangle().fill(Color.white.opacity(0.18))
                    .frame(width: 1, height: side * 0.7)
            }
        }
        .frame(width: a.edge.isVertical ? side : 10,
               height: a.edge.isVertical ? 10 : side)
    }

    // MARK: Icon tile

    private var iconTile: some View {
        VStack(spacing: 2) {
            ZStack {
                iconImage
                if item.kind == .folder, let letter = item.letter, !letter.isEmpty {
                    Text(letter)
                        .font(.system(size: side * 0.34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                }
            }
            .frame(width: side, height: side)
            if a.showLabels {
                Text(item.title)
                    .font(.system(size: max(7, side * 0.18), weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .frame(width: side * 1.4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { activate() }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard item.kind == .app || item.kind == .folder else { return false }
            collectURLs(providers) { urls in handleDrop(urls) }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .strokeBorder(profile.color, lineWidth: 2)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .help(item.title)
    }

    @ViewBuilder
    private var iconImage: some View {
        switch item.kind {
        case .app, .file:
            if let path = item.path, FileManager.default.fileExists(atPath: path) {
                Image(nsImage: IconProvider.shared.icon(forPath: path, side: side * 2))
                    .resizable().scaledToFit()
            } else {
                missingIcon
            }
        case .folder:
            folderIcon
        case .url:
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [tintColor.opacity(0.95), tintColor.opacity(0.65)],
                                         startPoint: .top, endPoint: .bottom))
                Image(systemName: item.symbol ?? "globe")
                    .font(.system(size: side * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .shortcut:
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#BF5AF2")!, Color(hex: "#5B8CFF")!],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: side * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .trash:
            Image(nsImage: trash.icon).resizable().scaledToFit()
        default:
            missingIcon
        }
    }

    private var folderIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [tintColor.opacity(0.95), tintColor.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            if item.letter?.isEmpty ?? true {
                Image(systemName: "folder.fill")
                    .font(.system(size: side * 0.42))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var missingIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .fill(Color.white.opacity(0.10))
            Image(systemName: "questionmark")
                .font(.system(size: side * 0.4, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var tintColor: Color {
        item.tint.flatMap { Color(hex: $0) } ?? profile.color
    }

    // MARK: Running indicator

    @ViewBuilder
    private var badge: some View {
        if item.kind == .app, let text = badgeText {
            Text(text)
                .font(.system(size: max(7, side * 0.22), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, side * 0.09)
                .padding(.vertical, side * 0.02)
                .frame(minWidth: side * 0.34)
                .background(
                    Capsule()
                        .fill(Color(hex: "#FF3B30")!)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.85),
                                                        lineWidth: side * 0.025))
                )
                .offset(x: side * 0.14, y: -side * 0.10)
                .transition(.scale)
        }
    }

    @ViewBuilder
    private var runningDot: some View {
        if item.kind == .app, isRunning {
            Circle()
                .fill(profile.color)
                .frame(width: side * 0.09, height: side * 0.09)
                .offset(y: side * 0.13)
        }
    }

    private var badgeText: String? {
        guard store.library.settings.showAppBadges, let path = item.path else { return nil }
        return badges.badge(forPath: path)
    }

    private var isRunning: Bool {
        guard let path = item.path else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.path == path
        }
    }

    // MARK: Actions

    private func activate() {
        switch item.kind {
        case .app:
            guard let url = item.fileURL else { NSSound.beep(); return }
            // Clicking a running app should bring it forward, not relaunch it.
            if running.isRunning(url.path) { running.activate(url.path) }
            else {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        case .folder:
            guard let url = item.fileURL else { NSSound.beep(); return }
            if item.folderAction == .stack {
                StackPanelController.shared.toggle(folder: url, near: screenRect,
                                                   edge: a.edge, accent: profile.color)
            } else {
                NSWorkspace.shared.open(url)
            }
        case .file:
            guard let url = item.fileURL else { NSSound.beep(); return }
            NSWorkspace.shared.open(url)
        case .trash:
            TrashService.shared.open()
        case .url:
            guard let raw = item.link,
                  let url = URL(string: raw.contains("://") ? raw : "https://\(raw)")
            else { NSSound.beep(); return }
            NSWorkspace.shared.open(url)
        case .shortcut:
            ShortcutsRunner.shared.run(item.shortcutName ?? "")
        case .spacer, .divider, .widget:
            break
        }
    }

    /// Dropping files on an app opens them with it; dropping on a folder moves
    /// them in, which is what both do in the system Dock.
    private func handleDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let path = item.path else { return }
        switch item.kind {
        case .app:
            running.open(urls, with: path)
        case .folder:
            let destination = URL(fileURLWithPath: path)
            for url in urls {
                let target = destination.appendingPathComponent(url.lastPathComponent)
                do { try FileManager.default.moveItem(at: url, to: target) }
                catch {
                    NSLog("Dockly: could not move \(url.lastPathComponent) — \(error.localizedDescription)")
                    NSSound.beep()
                }
            }
        default:
            break
        }
    }

    // MARK: Menu

    @ViewBuilder
    private var menu: some View {
        if item.kind == .trash {
            Button(L("Open Trash")) { trash.open() }
            Button(L("Empty Trash…")) { trash.empty() }
                .disabled(trash.isEmpty)
        }
        if item.kind == .app, let path = item.path {
            AppTileMenu(
                path: path,
                isPinned: true,
                onPin: {},
                onUnpin: { store.removeItem(item.id, from: profile.id) })
        }
        if item.kind == .file || item.kind == .folder {
            Button(L("Open")) { activate() }
            Button(L("Show in Finder")) {
                guard let url = item.fileURL else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            if item.kind == .folder {
                Divider()
                Picker(L("Click behaviour"), selection: Binding(
                    get: { item.folderAction },
                    set: { new in
                        store.update(profile.id) { p in
                            guard let i = p.items.firstIndex(where: { $0.id == item.id })
                            else { return }
                            p.items[i].folderAction = new
                        }
                    })) {
                    ForEach(FolderAction.allCases) { Text($0.title).tag($0) }
                }
                Menu(L("Color")) {
                    ForEach(Color.docklyPalette, id: \.self) { hex in
                        Button(hex) { setTint(hex) }
                    }
                }
            }
        }
        if item.kind == .widget {
            Button(L("Widget settings…")) { SettingsWindowController.shared.show(tab: .setups) }
        }
        Divider()
        Button(L("Remove from Dock")) { store.removeItem(item.id, from: profile.id) }
        Button(L("Dockly Settings…")) { SettingsWindowController.shared.show(tab: .setups) }
    }

    private func setTint(_ hex: String) {
        store.update(profile.id) { p in
            guard let i = p.items.firstIndex(where: { $0.id == item.id }) else { return }
            p.items[i].tint = hex
        }
    }
}

// MARK: - Reordering

struct SlotDropDelegate: DropDelegate {
    var index: Int
    var profileID: UUID
    var store: DocklyStore

    func performDrop(info: DropInfo) -> Bool {
        if let provider = info.itemProviders(for: [UTType.text.identifier]).first {
            provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let raw = value as? String, let id = UUID(uuidString: raw) else { return }
                DispatchQueue.main.async {
                    guard let profile = store.profile(profileID),
                          let from = profile.items.firstIndex(where: { $0.id == id })
                    else { return }
                    store.moveItem(in: profileID, from: from, to: index)
                }
            }
            return true
        }
        let fileProviders = info.itemProviders(for: [UTType.fileURL.identifier])
        guard !fileProviders.isEmpty else { return false }
        for p in fileProviders {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    store.addItem(DockItem.make(from: url), to: profileID, at: index)
                }
            }
        }
        return true
    }
}
