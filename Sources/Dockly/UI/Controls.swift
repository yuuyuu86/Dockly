import SwiftUI
import AppKit

// MARK: - Hotkey field

struct HotkeyField: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording.toggle()
            } label: {
                Text(recording ? "Press keys…" : (hotkey?.display ?? "Click to record"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(width: 150, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(recording ? Color.accentColor.opacity(0.2)
                                            : Color.primary.opacity(0.07))
                    )
            }
            .buttonStyle(.plain)
            .background(
                HotkeyRecorderRepresentable(active: $recording) { hk in
                    hotkey = hk
                    recording = false
                }
                .frame(width: 0, height: 0)
            )

            if hotkey != nil {
                Button(L("Clear")) { hotkey = nil }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
        }
    }
}

struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var active: Bool
    var onCapture: (Hotkey) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderView {
        let v = HotkeyRecorderView()
        v.onCapture = onCapture
        v.onCancel = { active = false }
        return v
    }

    func updateNSView(_ v: HotkeyRecorderView, context: Context) {
        v.onCapture = onCapture
        if active, v.window?.firstResponder !== v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
    }
}

// MARK: - Focus mode picker

struct FocusModePicker: View {
    var profileID: UUID
    @EnvironmentObject private var store: DocklyStore
    @ObservedObject private var focus = FocusMonitor.shared

    var body: some View {
        Picker("", selection: Binding(
            get: { store.profile(profileID)?.focusModeID ?? "" },
            set: { new in
                store.update(profileID) { $0.focusModeID = new.isEmpty ? nil : new }
            })
        ) {
            Text(L("Never")).tag("")
            Divider()
            ForEach(focus.availableModes) { mode in
                Text(mode.name).tag(mode.id)
            }
        }
        .labelsHidden()
        .frame(width: 200)
        .onAppear { focus.reloadModes() }
    }
}

// MARK: - Per-item settings

struct ItemSettingsEditor: View {
    var item: DockItem
    var profileID: UUID
    @EnvironmentObject private var store: DocklyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item.kind {
            case .spacer:
                HStack {
                    Text(L("Width")).frame(width: 90, alignment: .leading)
                    Slider(value: field(\.spacerWidth), in: 4...120)
                        .frame(width: 180)
                    Text("\(Int(item.spacerWidth)) pt").font(.system(size: 11, design: .rounded))
                }
            case .folder:
                HStack {
                    Text(L("Letter")).frame(width: 90, alignment: .leading)
                    TextField("", text: Binding(
                        get: { item.letter ?? "" },
                        set: { v in mutate { $0.letter = String(v.prefix(2)).uppercased() } }))
                    .frame(width: 50)
                }
                colorRow
            case .url:
                HStack {
                    Text(L("Address")).frame(width: 90, alignment: .leading)
                    TextField(L("https://"), text: Binding(
                        get: { item.link ?? "" },
                        set: { v in mutate { $0.link = v } }))
                    .frame(width: 240)
                }
                colorRow
            case .shortcut:
                HStack {
                    Text(L("Shortcut")).frame(width: 90, alignment: .leading)
                    ShortcutPicker(current: item.shortcutName ?? "") { name in
                        mutate { $0.shortcutName = name; $0.title = name }
                    }
                }
            case .widget:
                WidgetSettingsEditor(item: item, profileID: profileID)
            default:
                EmptyView()
            }
        }
        .font(.system(size: 12))
    }

    private var colorRow: some View {
        HStack {
            Text(L("Color")).frame(width: 90, alignment: .leading)
            ForEach(Color.docklyPalette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.primary.opacity(item.tint == hex ? 0.9 : 0),
                                                   lineWidth: 2))
                    .onTapGesture { mutate { $0.tint = hex } }
            }
        }
    }

    private func field(_ key: WritableKeyPath<DockItem, Double>) -> Binding<Double> {
        Binding(get: { item[keyPath: key] },
                set: { v in mutate { $0[keyPath: key] = v } })
    }

    private func mutate(_ body: @escaping (inout DockItem) -> Void) {
        store.update(profileID) { p in
            guard let i = p.items.firstIndex(where: { $0.id == item.id }) else { return }
            body(&p.items[i])
        }
    }
}

struct ShortcutPicker: View {
    var current: String
    var onPick: (String) -> Void
    @ObservedObject private var runner = ShortcutsRunner.shared

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { current }, set: onPick)) {
                Text(L("None")).tag("")
                ForEach(runner.names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
            Button(L("Reload")) { runner.reload() }
                .buttonStyle(.borderless).font(.system(size: 11))
        }
        .onAppear { if runner.names.isEmpty { runner.reload() } }
    }
}
