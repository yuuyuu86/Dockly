import AppKit
import SwiftUI

/// The grid a folder tile opens — the equivalent of a Dock stack.
///
/// It lives in its own borderless panel rather than a SwiftUI popover: the
/// dock itself never becomes key, and popovers anchored to a non-activating
/// panel misbehave.
@MainActor
final class StackPanelController {
    static let shared = StackPanelController()

    private var panel: NSPanel?
    private var openFolder: URL?
    private var dismissMonitor: Any?

    private init() {}

    var isOpen: Bool { panel?.isVisible ?? false }

    func toggle(folder: URL, near rect: CGRect, edge: DockEdge, accent: Color) {
        if isOpen, openFolder == folder { close(); return }
        show(folder: folder, near: rect, edge: edge, accent: accent)
    }

    func show(folder: URL, near rect: CGRect, edge: DockEdge, accent: Color) {
        close()
        let entries = Self.contents(of: folder)
        let view = StackView(folder: folder, entries: entries, accent: accent) { [weak self] in
            self?.close()
        }

        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        panel.setFrame(NSRect(origin: Self.origin(for: size, near: rect, edge: edge),
                              size: size), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        openFolder = folder
        installDismissMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        openFolder = nil
        if let m = dismissMonitor { NSEvent.removeMonitor(m); dismissMonitor = nil }
    }

    private func installDismissMonitor() {
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private static func origin(for size: CGSize, near rect: CGRect, edge: DockEdge) -> CGPoint {
        let gap: CGFloat = 10
        let screen = NSScreen.screens.first { NSPointInRect(CGPoint(x: rect.midX, y: rect.midY),
                                                           $0.frame) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero

        var origin = CGPoint.zero
        switch edge {
        case .bottom:
            origin = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + gap)
        case .top:
            origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - gap)
        case .left:
            origin = CGPoint(x: rect.maxX + gap, y: rect.midY - size.height / 2)
        case .right:
            origin = CGPoint(x: rect.minX - size.width - gap, y: rect.midY - size.height / 2)
        }
        // Keep it on screen.
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        return origin
    }

    // MARK: Contents

    struct Entry: Identifiable, Hashable {
        var id: String { url.path }
        var url: URL
        var name: String
        var isDirectory: Bool
    }

    static func contents(of folder: URL, limit: Int = 40) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .localizedNameKey,
                                      .contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles])) ?? []

        return items
            .sorted { a, b in
                a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
            .prefix(limit)
            .map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Entry(url: url,
                             name: values?.localizedName ?? url.lastPathComponent,
                             isDirectory: values?.isDirectory ?? false)
            }
    }
}

// MARK: - The grid itself

private struct StackView: View {
    var folder: URL
    var entries: [StackPanelController.Entry]
    var accent: Color
    var onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(accent)
                Text(folder.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 12)
                Button(L("Open in Finder")) {
                    NSWorkspace.shared.open(folder)
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent)
            }

            if entries.isEmpty {
                Text(L("This folder is empty."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(entries) { entry in
                            StackTile(entry: entry, onOpen: {
                                NSWorkspace.shared.open(entry.url)
                                onDismiss()
                            })
                        }
                    }
                }
                .frame(width: 340, height: entries.count > 15 ? 260 : nil)
                .fixedSize(horizontal: false, vertical: entries.count <= 15)
            }
        }
        .padding(12)
        .frame(minWidth: 260)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.16))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StackTile: View {
    var entry: StackPanelController.Entry
    var onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 3) {
                Image(nsImage: IconProvider.shared.icon(forPath: entry.url.path, side: 72))
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                Text(entry.name)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 24, alignment: .top)
            }
            .frame(width: 74)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.14 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.name)
    }
}
