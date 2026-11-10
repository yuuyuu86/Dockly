import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Battery

struct BatteryWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = BatterySource.shared

    var body: some View {
        let s = source.state
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    RingGauge(progress: Double(s.percent) / 100, color: color(s),
                              lineWidth: context.pt(3))
                    Image(systemName: s.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: context.pt(8), weight: .bold))
                        .foregroundStyle(color(s))
                }
                .frame(width: context.pt(26), height: context.pt(26))

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: "\(s.percent)%", context: context, size: 14)
                    WidgetCaption(text: subtitle(s), context: context)
                }
            }
        }
        .help(L("Battery"))
    }

    private func color(_ s: BatteryState) -> Color {
        if s.isCharging { return Color(hex: "#34C759")! }
        if s.percent <= 10 { return Color(hex: "#FF375F")! }
        if s.percent <= 20 { return Color(hex: "#FF9F0A")! }
        return .white
    }

    private func subtitle(_ s: BatteryState) -> String {
        if let m = s.minutesRemaining {
            let text = L("%1$dh %2$dm", m / 60, m % 60)
            return s.isCharging ? L("%@ to full", text) : L("%@ left", text)
        }
        if s.isPluggedIn { return s.isCharging ? L("Charging") : L("Plugged in") }
        return L("On battery")
    }
}

// MARK: - System Activity

struct SystemActivityWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = ActivitySource.shared

    var body: some View {
        let s = source.sample
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(9)) {
                gauge(label: "CPU", value: s.cpu, color: context.accent)
                gauge(label: "MEM", value: s.memory, color: Color(hex: "#BF5AF2")!)
                Sparkline(values: s.history, color: context.accent)
                    .frame(width: context.pt(34))
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath:
                "/System/Applications/Utilities/Activity Monitor.app"))
        }
        .help(String(format: L("CPU %1$.0f%% · Memory %2$.1f of %3$.0f GB"),
                     s.cpu * 100, s.memoryUsedGB, s.memoryTotalGB))
    }

    private func gauge(label: String, value: Double, color: Color) -> some View {
        ZStack {
            RingGauge(progress: value, color: color, lineWidth: context.pt(3))
            VStack(spacing: -1) {
                Text("\(Int(round(value * 100)))")
                    .font(.system(size: context.pt(9.5), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: context.pt(5.5), weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: context.pt(28), height: context.pt(28))
    }
}

// MARK: - Network Activity

struct NetworkActivityWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = NetworkSource.shared

    var body: some View {
        let s = source.sample
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                VStack(alignment: .leading, spacing: context.pt(1)) {
                    row(symbol: "arrow.down", text: s.downBytesPerSecond.byteRateString,
                        color: Color(hex: "#34C759")!)
                    row(symbol: "arrow.up", text: s.upBytesPerSecond.byteRateString,
                        color: Color(hex: "#64D2FF")!)
                }
                Sparkline(values: s.downHistory, color: Color(hex: "#34C759")!)
                    .frame(width: context.pt(32))
            }
        }
        .help(L("Network activity"))
    }

    private func row(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: context.pt(3)) {
            Image(systemName: symbol)
                .font(.system(size: context.pt(7), weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: context.pt(9.5), weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - AirDrop

struct AirDropWidget: View {
    var context: WidgetContext
    @State private var targeted = false

    var body: some View {
        WidgetPlate(context: context, tint: targeted ? context.accent : nil) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    Circle().fill(Color(hex: "#5B8CFF")!.opacity(targeted ? 0.45 : 0.22))
                    Image(systemName: "wifi")
                        .font(.system(size: context.pt(12), weight: .bold))
                        .foregroundStyle(Color(hex: "#5B8CFF")!)
                        .rotationEffect(.degrees(45))
                }
                .frame(width: context.pt(26), height: context.pt(26))
                .scaleEffect(targeted ? 1.08 : 1)
                .animation(.spring(response: 0.25), value: targeted)

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: L("AirDrop"), context: context, size: 13)
                    WidgetCaption(text: targeted ? L("Release to send") : L("Drop files here"),
                                  context: context)
                }
            }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $targeted) { providers in
            collect(providers) { items in
                guard !items.isEmpty else { return }
                AirDropService.send(items, from: nil)
            }
            return true
        }
        .onTapGesture(count: 2) { AirDropService.openAirDropWindow() }
        .help(L("AirDrop — drop files to send"))
    }

    private func collect(_ providers: [NSItemProvider], done: @escaping ([Any]) -> Void) {
        var items: [Any] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { items.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(items) }
    }
}

// MARK: - Shortcut

struct ShortcutWidget: View {
    var context: WidgetContext
    @ObservedObject private var runner = ShortcutsRunner.shared
    @ObservedObject private var store = DocklyStore.shared
    @State private var flash = false

    private var name: String { context.instance.string("name", "") }

    var body: some View {
        let busy = runner.running.contains(name)
        WidgetPlate(context: context, tint: flash ? Color(hex: "#34C759") : nil) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    Circle().fill(Color(hex: "#BF5AF2")!.opacity(0.22))
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: context.pt(11), weight: .bold))
                            .foregroundStyle(Color(hex: "#BF5AF2")!)
                    }
                }
                .frame(width: context.pt(26), height: context.pt(26))

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: name.isEmpty ? L("Pick a Shortcut") : name,
                                context: context, size: 12)
                    WidgetCaption(text: busy ? L("Running…") : L("Shortcut"), context: context)
                }
            }
        }
        .onTapGesture { run() }
        .contextMenu {
            if runner.names.isEmpty {
                Button(L("Load Shortcuts")) { runner.reload() }
            } else {
                ForEach(runner.names.prefix(40), id: \.self) { n in
                    Button(n) { store.setWidgetSetting(context.id, "name", n) }
                }
            }
            Divider()
            Button(L("Open Shortcuts app")) { runner.openShortcutsApp() }
        }
        .onAppear { if runner.names.isEmpty { runner.reload() } }
        .help(name.isEmpty ? L("Right-click to pick a Shortcut") : L("Run “%@”", name))
    }

    private func run() {
        guard !name.isEmpty else { runner.reload(); return }
        runner.run(name) { ok in
            guard ok else { NSSound.beep(); return }
            withAnimation { flash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation { flash = false }
            }
        }
    }
}

// MARK: - Revenue (Stripe / Paddle)

struct RevenueWidget: View {
    var context: WidgetContext
    @ObservedObject private var source: RevenueSource

    init(context: WidgetContext) {
        self.context = context
        _source = ObservedObject(wrappedValue: RevenueSource.source(for: context.kind))
    }

    private var label: String { context.instance.string("label", context.kind.title) }

    var body: some View {
        let s = source.snapshot
        let brand = context.kind == .stripe ? Color(hex: "#635BFF")! : Color(hex: "#FDDD35")!

        WidgetPlate(context: context, tint: brand) {
            HStack(spacing: context.pt(9)) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetCaption(text: label, context: context)
                    WidgetValue(text: s.error == nil ? s.formatted : "—",
                                context: context, size: 16)
                    WidgetCaption(text: s.error ?? s.secondary, context: context)
                }
                if !s.trend.isEmpty {
                    Sparkline(values: s.trend, color: brand)
                        .frame(width: context.pt(38))
                }
            }
        }
        .onAppear { source.refresh() }
        .contextMenu {
            Button(L("Refresh now")) { source.refresh(force: true) }
            Button(L("Open Dockly settings…")) { SettingsWindowController.shared.show(tab: .widgets) }
        }
        .help(s.error ?? L("Month to date · updated %@",
                           s.updated.formatted(date: .omitted, time: .shortened)))
    }
}

// MARK: - Recent Apps

/// The system Dock keeps a short list of apps you have used lately; this is
/// that, in a widget, with the pinned apps filtered out so it never shows you
/// something already sitting a few pixels away.
struct RecentAppsWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = RecentAppsSource.shared
    @EnvironmentObject private var store: DocklyStore
    @State private var hovered: String?

    private var count: Int { context.instance.int("count", 3) }
    private var hidesPinned: Bool { context.instance.bool("hidePinned", true) }

    private var pinned: Set<String> {
        guard hidesPinned, let profile = store.profile(context.profileID) else { return [] }
        return Set(profile.items.compactMap { $0.kind == .app ? $0.path : nil })
    }

    var body: some View {
        let entries = source.top(count, excluding: pinned)
        // No plate: these are app icons, and they should read as part of the
        // dock rather than as a panel sitting inside it.
        HStack(spacing: context.pt(7)) {
            if entries.isEmpty {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: context.pt(15), weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: context.height, height: context.height)
                    .help(L("No recents"))
            } else {
                ForEach(entries) { entry in
                    tile(entry)
                }
            }
        }
        .frame(height: context.height)
        .contextMenu { settingsMenu }
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Picker(L("How many"), selection: Binding(
            get: { count },
            set: { store.setWidgetSetting(context.id, "count", String($0)) })) {
            ForEach(1...6, id: \.self) { Text("\($0)").tag($0) }
        }
        Toggle(L("Hide apps already in this dock"), isOn: Binding(
            get: { hidesPinned },
            set: { store.setWidgetSetting(context.id, "hidePinned", $0 ? "true" : "false") }))
        Divider()
        Button(L("Clear recents")) { source.clear() }
    }

    private func tile(_ entry: RecentAppsSource.Entry) -> some View {
        // Leave room for the running dot so the icons line up with the pinned
        // ones either side of the widget.
        let side = context.height - context.pt(6)
        return VStack(spacing: context.pt(2)) {
            Image(nsImage: IconProvider.shared.icon(forPath: entry.path, side: side * 2))
                .resizable().scaledToFit()
                .frame(width: side, height: side)
            Circle()
                .fill(context.accent)
                .frame(width: side * 0.09, height: side * 0.09)
                .opacity(entry.isRunning ? 1 : 0)
        }
        .frame(height: context.height)
        .scaleEffect(hovered == entry.path ? 1.18 : 1, anchor: .bottom)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? entry.path : (hovered == entry.path ? nil : hovered) }
        .onTapGesture { source.activate(entry.path) }
        .contextMenu {
            AppTileMenu(
                path: entry.path,
                isPinned: false,
                onPin: { store.addItem(DockItem.make(from: URL(fileURLWithPath: entry.path)),
                                       to: context.profileID) },
                onUnpin: {})
        }
        .help(entry.name)
        .accessibilityLabel(entry.name)
    }
}
