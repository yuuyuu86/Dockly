import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case setups, widgets, appearance, focus, general, backup, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .setups:     return L("Setups")
        case .widgets:    return L("Widgets")
        case .appearance: return L("Appearance")
        case .focus:      return L("Focus")
        case .general:    return L("General")
        case .backup:     return L("Backup")
        case .about:      return L("About")
        }
    }
    var symbol: String {
        switch self {
        case .setups:     return "square.stack.3d.up.fill"
        case .widgets:    return "square.grid.2x2.fill"
        case .appearance: return "paintbrush.fill"
        case .focus:      return "moon.fill"
        case .general:    return "gearshape.fill"
        case .backup:     return "arrow.down.doc.fill"
        case .about:      return "info.circle.fill"
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(tab: SettingsTab = .setups) {
        selection.tab = tab
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsRootView()
            .environmentObject(DocklyStore.shared)
            .environmentObject(selection)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = "Dockly"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: root)
        w.minSize = NSSize(width: 820, height: 540)
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        DocklyStore.shared.saveNow()
    }
}

final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .setups
    @Published var profileID: UUID?
}

// MARK: - Root

struct SettingsRootView: View {
    @EnvironmentObject private var store: DocklyStore
    @EnvironmentObject private var selection: SettingsSelection

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear {
            if selection.profileID == nil { selection.profileID = store.library.activeProfileID }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "dock.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(L("Dockly"))
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.top, 34)
            .padding(.bottom, 12)

            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection.tab = tab
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: tab.symbol)
                            .frame(width: 17)
                            .foregroundStyle(selection.tab == tab ? Color.accentColor : .secondary)
                        Text(tab.title)
                            .font(.system(size: 13, weight: selection.tab == tab ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection.tab == tab ? Color.primary.opacity(0.08) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .noFocusRing()
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 3) {
                Text(L("Active setup"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle().fill(store.activeProfile.color).frame(width: 7, height: 7)
                    Text(store.activeProfile.name)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 190)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.tab {
        case .setups:     SetupsPane()
        case .widgets:    WidgetGalleryPane()
        case .appearance: AppearancePane()
        case .focus:      FocusPane()
        case .general:    GeneralPane()
        case .backup:     BackupPane()
        case .about:      AboutPane()
        }
    }
}

// MARK: - Shared bits

struct PaneHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }
}

struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
        }
    }
}


extension View {
    /// Sidebar rows carry their own selection styling; the system focus ring
    /// on top of it reads as a second, conflicting selection.
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) { self.focusEffectDisabled() } else { self }
    }
}
