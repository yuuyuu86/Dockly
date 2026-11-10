import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The whole floating dock: plate, tiles, widgets and the switch banner.
struct DockContainerView: View {
    var profile: DockProfile
    var banner: String?

    @EnvironmentObject private var store: DocklyStore
    @ObservedObject private var running = RunningAppsMonitor.shared
    @State private var hoveredIndex: Int?
    @State private var hoveredMagnifies = false
    @State private var dropIndex: Int?

    private var a: DockAppearance { profile.appearance }
    /// Extra room so a magnified icon is never clipped.
    private var overhang: CGFloat { a.magnificationEnabled ? CGFloat(a.iconSize) * 0.55 : 6 }

    var body: some View {
        ZStack(alignment: bannerAlignment) {
            plate
            if let banner { switchBanner(banner) }
        }
        .padding(overhangInsets)
        .fixedSize()
    }

    // MARK: Plate

    /// The pinned items, plus anything the appearance adds automatically.
    private var displayedItems: [DockItem] {
        var items = profile.items

        if a.showRunningApps {
            let pinned = Set(items.compactMap { $0.kind == .app ? $0.path : nil })
            let extras = running.apps
                .filter { !pinned.contains($0.path) }
                .map { entry -> DockItem in
                    var item = DockItem(kind: .app, title: entry.name, path: entry.path)
                    // A stable id keeps SwiftUI from rebuilding the tile on
                    // every activation change.
                    item.id = UUID(uuidString: Self.stableID(for: entry.path)) ?? item.id
                    return item
                }
            if !extras.isEmpty {
                if !items.isEmpty { items.append(DockItem(kind: .divider)) }
                items.append(contentsOf: extras)
            }
        }

        if a.showTrash, !items.contains(where: { $0.kind == .trash }) {
            if !items.isEmpty { items.append(DockItem(kind: .divider)) }
            items.append(DockItem(kind: .trash, title: "Trash"))
        }
        return items
    }

    /// A UUID derived from a path, so auto-added tiles keep their identity.
    private static func stableID(for path: String) -> String {
        var hash = UInt64(14695981039346656037)
        for byte in path.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        let hex = String(format: "%016lX%016lX", hash, hash &* 31)
        let s = Array(hex)
        return "\(String(s[0..<8]))-\(String(s[8..<12]))-\(String(s[12..<16]))-" +
               "\(String(s[16..<20]))-\(String(s[20..<32]))"
    }

    private var plate: some View {
        stack {
            let items = displayedItems
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DockSlotView(
                    item: item,
                    index: index,
                    profile: profile,
                    hoveredIndex: $hoveredIndex,
                    hoveredMagnifies: $hoveredMagnifies,
                    dropIndex: $dropIndex
                )
            }
            if items.isEmpty { emptyHint }
        }
        .padding(CGFloat(a.padding))
        .background(
            plateBackground
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(a.cornerRadius), style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(a.cornerRadius),
                                            style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 18, y: a.edge == .top ? -6 : 6)
        )
        .opacity(a.opacity)
        .onDrop(of: [.fileURL], delegate: DockPlateDropDelegate(profileID: profile.id, store: store))
    }

    @ViewBuilder
    private func stack<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if a.edge.isVertical {
            VStack(alignment: .center, spacing: CGFloat(a.spacing)) { content() }
        } else {
            HStack(alignment: .center, spacing: CGFloat(a.spacing)) { content() }
        }
    }

    private var plateBackground: some View {
        ZStack {
            if a.material == .solid {
                RoundedRectangle(cornerRadius: CGFloat(a.cornerRadius), style: .continuous)
                    .fill(Color.black.opacity(0.82))
            } else {
                VisualEffectBackground(material: nsMaterial)
                RoundedRectangle(cornerRadius: CGFloat(a.cornerRadius), style: .continuous)
                    .fill(Color.black.opacity(0.18))
            }
        }
    }

    private var nsMaterial: NSVisualEffectView.Material {
        switch a.material {
        case .regular:   return .hudWindow
        case .thick:     return .underWindowBackground
        case .thin:      return .popover
        case .ultraThin: return .menu
        case .solid:     return .hudWindow
        }
    }

    private var emptyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.rectangle")
            Text(L("Drop apps here, or open Dockly settings"))
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.55))
        .frame(height: CGFloat(a.iconSize))
        .padding(.horizontal, 10)
        .onTapGesture { SettingsWindowController.shared.show(tab: .setups) }
    }

    // MARK: Banner

    private var bannerAlignment: Alignment {
        switch a.edge {
        case .bottom: return .top
        case .top:    return .bottom
        case .left:   return .trailing
        case .right:  return .leading
        }
    }

    private func switchBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: profile.symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(profile.color.opacity(0.9)))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        .offset(y: a.edge == .bottom ? -6 : (a.edge == .top ? 6 : 0))
        .transition(.opacity.combined(with: .scale))
    }

    private var overhangInsets: EdgeInsets {
        EdgeInsets(top: overhang, leading: overhang, bottom: overhang, trailing: overhang)
    }
}

/// NSVisualEffectView wrapper — SwiftUI's `.ultraThinMaterial` does not blur
/// what is *behind the window*, which is exactly what a dock needs.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

// MARK: - Dropping files onto the dock

struct DockPlateDropDelegate: DropDelegate {
    var profileID: UUID
    var store: DocklyStore

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    store.addItem(DockItem.make(from: url), to: profileID)
                }
            }
        }
        return true
    }
}

extension DockItem {
    /// Builds the right kind of tile for whatever the user dropped.
    static func make(from url: URL) -> DockItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
        let isApp: Bool = values?.isApplication ?? (url.pathExtension == "app")
        let isDir: Bool = values?.isDirectory ?? false

        let name = url.deletingPathExtension().lastPathComponent
        if isApp {
            var item = DockItem(kind: .app, title: name, path: url.path)
            item.bundleID = Bundle(url: url)?.bundleIdentifier
            return item
        }
        if isDir {
            let hex: String = Color.docklyPalette.randomElement() ?? "#5B8CFF"
            return DockItem(kind: .folder, title: name, path: url.path,
                            tint: hex,
                            letter: String(name.prefix(1)).uppercased())
        }
        return DockItem(kind: .file, title: name, path: url.path)
    }
}
