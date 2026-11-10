import SwiftUI
import AppKit

// MARK: - Volume

struct VolumeWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = VolumeSource.shared
    @State private var dragging = false

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                Button {
                    source.toggleMute()
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: context.pt(13), weight: .medium))
                        .foregroundStyle(source.isMuted ? .white.opacity(0.4) : .white)
                        .frame(width: context.pt(18))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: context.pt(3)) {
                    slider
                    WidgetCaption(text: source.currentDeviceName.isEmpty
                                  ? L("Volume") : source.currentDeviceName,
                                  context: context)
                }
            }
        }
        .contextMenu {
            ForEach(source.devices) { device in
                Button(device.name) { source.select(device) }
            }
            Divider()
            Button(L("Refresh")) { source.refresh() }
        }
        .help(L("Volume %d%%", Int(round(source.level * 100))))
    }

    private var symbol: String {
        if source.isMuted || source.level == 0 { return "speaker.slash.fill" }
        if source.level < 0.34 { return "speaker.wave.1.fill" }
        if source.level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var slider: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(source.isMuted ? Color.white.opacity(0.3) : .white)
                    .frame(width: max(2, width * source.level))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        source.setLevel(value.location.x / max(1, width))
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(width: context.pt(88), height: context.pt(6))
    }
}

// MARK: - Keep Awake

struct KeepAwakeWidget: View {
    var context: WidgetContext
    @ObservedObject private var service = KeepAwakeService.shared
    @ObservedObject private var engine = TimerEngine.shared
    @ObservedObject private var store = DocklyStore.shared

    private var minutes: Int { context.instance.int("minutes", 0) }

    var body: some View {
        let on = service.isActive
        WidgetPlate(context: context, tint: on ? Color(hex: "#FF9F0A") : nil) {
            HStack(spacing: context.pt(8)) {
                Image(systemName: on ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: context.pt(14), weight: .medium))
                    .foregroundStyle(on ? Color(hex: "#FF9F0A")! : .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: on ? L("Awake") : L("Off"), context: context, size: 13)
                    WidgetCaption(text: caption, context: context)
                }
            }
        }
        .onTapGesture { service.toggle(minutes: minutes) }
        .contextMenu {
            Picker(L("Keep awake for"), selection: Binding(
                get: { minutes },
                set: { store.setWidgetSetting(context.id, "minutes", String($0)) })) {
                Text(L("Until I turn it off")).tag(0)
                Text(L("15 minutes")).tag(15)
                Text(L("30 minutes")).tag(30)
                Text(L("1 hour")).tag(60)
                Text(L("2 hours")).tag(120)
            }
        }
        .help(L("Keeps the display and Mac awake"))
    }

    private var caption: String {
        guard service.isActive else { return L("Keep Awake") }
        guard let endsAt = service.endsAt else { return L("No sleep") }
        let left = max(0, endsAt.timeIntervalSince(engine.tick))
        return L("%d min left", Int(left / 60) + 1)
    }
}

// MARK: - Disk Space

struct DiskSpaceWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = DiskSource.shared

    var body: some View {
        let u = source.usage
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    RingGauge(progress: u.usedFraction, color: color(u),
                              lineWidth: context.pt(3))
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: context.pt(8), weight: .bold))
                        .foregroundStyle(color(u))
                }
                .frame(width: context.pt(26), height: context.pt(26))

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: u.freeString, context: context, size: 14)
                    WidgetCaption(text: L("Free"), context: context)
                }
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/"))
        }
        .contextMenu {
            Button(L("Refresh")) { source.refresh() }
            Button(L("Open Storage settings")) {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.settings.Storage")!)
            }
        }
        .help(L("%1$@ free of %2$@ on %3$@", u.freeString, u.totalString, u.name))
    }

    private func color(_ u: DiskUsage) -> Color {
        if u.usedFraction > 0.92 { return Color(hex: "#FF375F")! }
        if u.usedFraction > 0.8 { return Color(hex: "#FF9F0A")! }
        return context.accent
    }
}

// MARK: - Bluetooth batteries

struct BluetoothBatteryWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = BluetoothSource.shared

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(10)) {
                if source.devices.isEmpty {
                    Image(systemName: "dot.radiowaves.right")
                        .font(.system(size: context.pt(13)))
                        .foregroundStyle(.white.opacity(0.45))
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetValue(text: L("Nothing connected"), context: context, size: 12)
                        WidgetCaption(text: L("Bluetooth"), context: context)
                    }
                } else {
                    ForEach(source.devices.prefix(3)) { device in
                        HStack(spacing: context.pt(5)) {
                            Image(systemName: device.symbol)
                                .font(.system(size: context.pt(12)))
                                .foregroundStyle(color(device.percent))
                            VStack(alignment: .leading, spacing: 0) {
                                WidgetValue(text: "\(device.percent)%", context: context, size: 12)
                                WidgetCaption(text: device.name, context: context)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { source.refresh() }
        .contextMenu {
            Button(L("Refresh")) { source.refresh() }
            Button(L("Open Bluetooth settings")) {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension")!)
            }
        }
        .help(L("Bluetooth"))
    }

    private func color(_ percent: Int) -> Color {
        if percent <= 10 { return Color(hex: "#FF375F")! }
        if percent <= 20 { return Color(hex: "#FF9F0A")! }
        return .white
    }
}

// MARK: - Screenshot

struct ScreenshotWidget: View {
    var context: WidgetContext
    @ObservedObject private var store = DocklyStore.shared

    private var toClipboard: Bool { context.instance.bool("clipboard", false) }

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(4)) {
                button("selection", "viewfinder", L("Capture a selection")) {
                    ScreenshotActions.capture(.selection, toClipboard: toClipboard)
                }
                button("window", "macwindow", L("Capture a window")) {
                    ScreenshotActions.capture(.window, toClipboard: toClipboard)
                }
                button("screen", "rectangle.inset.filled", L("Capture the screen")) {
                    ScreenshotActions.capture(.screen, toClipboard: toClipboard)
                }
            }
        }
        .contextMenu {
            Toggle(L("Copy to clipboard instead of saving"), isOn: Binding(
                get: { toClipboard },
                set: { store.setWidgetSetting(context.id, "clipboard", $0 ? "true" : "false") }))
            Divider()
            Button(L("Open Screenshot app")) { ScreenshotActions.openScreenshotApp() }
        }
        .help(L("Screenshot"))
    }

    private func button(_ id: String, _ symbol: String, _ hint: String,
                        action: @escaping () -> Void) -> some View {
        WidgetButton(symbol: symbol, context: context, prominent: true, action: action)
            .help(hint)
    }
}

// MARK: - Clipboard history

struct ClipboardWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = ClipboardSource.shared
    @State private var justCopied: UUID?

    private var shown: Int { context.instance.int("rows", 2) }

    var body: some View {
        WidgetPlate(context: context, tint: source.isPaused ? nil : nil) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    Circle().fill(Color(hex: "#64D2FF")!.opacity(0.2))
                    Image(systemName: source.isPaused ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                        .font(.system(size: context.pt(11), weight: .semibold))
                        .foregroundStyle(Color(hex: "#64D2FF")!)
                }
                .frame(width: context.pt(24), height: context.pt(24))

                if source.entries.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetValue(text: L("Nothing copied yet"), context: context, size: 12)
                        WidgetCaption(text: L("Clipboard"), context: context)
                    }
                } else {
                    VStack(alignment: .leading, spacing: context.pt(2)) {
                        ForEach(source.entries.prefix(max(1, shown))) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .contextMenu { menu }
        .help(source.isPaused ? L("Clipboard — paused") : L("Clipboard"))
    }

    private func row(_ entry: ClipboardSource.Entry) -> some View {
        HStack(spacing: context.pt(5)) {
            Image(systemName: justCopied == entry.id ? "checkmark" : "doc.on.doc")
                .font(.system(size: context.pt(8), weight: .bold))
                .foregroundStyle(justCopied == entry.id
                                 ? Color(hex: "#34C759")! : .white.opacity(0.4))
            Text(entry.preview)
                .font(.system(size: context.pt(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(maxWidth: context.pt(150), alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            source.copy(entry)
            justCopied = entry.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if justCopied == entry.id { justCopied = nil }
            }
        }
        .help(entry.text)
    }

    @ViewBuilder
    private var menu: some View {
        ForEach(source.entries.prefix(10)) { entry in
            Button(entry.preview) { source.copy(entry) }
        }
        if !source.entries.isEmpty { Divider() }
        Toggle(L("Pause recording"), isOn: Binding(
            get: { source.isPaused }, set: { source.isPaused = $0 }))
        Button(L("Clear history")) { source.clear() }
        Text(L("History is kept in memory only and is never written to disk."))
    }
}
