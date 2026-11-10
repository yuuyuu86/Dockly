import SwiftUI
import AppKit

/// Per-widget configuration, shown inline under a dock item.
struct WidgetSettingsEditor: View {
    var item: DockItem
    var profileID: UUID
    @EnvironmentObject private var store: DocklyStore

    private var kind: WidgetKind { item.widget?.kind ?? .clock }
    private var inst: WidgetInstance { item.widget ?? WidgetInstance(kind: .clock) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .clock:
                toggle("24-hour time", "h24", true)
                toggle("Show seconds", "seconds", false)
                toggle("Show date", "date", true)

            case .worldClock:
                field("Time zones", "zones", "Europe/London,America/New_York", width: 280)
                Text(L("Comma separated IANA names, up to three."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                toggle("24-hour time", "h24", true)

            case .focusTimer:
                stepper("Focus minutes", "focus", 25, 1...120)
                stepper("Short break", "short", 5, 1...60)
                stepper("Long break", "long", 15, 1...90)

            case .countdown:
                field("Title", "title", "Countdown", width: 220)
                DatePickerRow(label: "Target",
                              value: Binding(
                                get: {
                                    inst["target"].flatMap { ISO8601DateFormatter().date(from: $0) }
                                        ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())!
                                },
                                set: { set("target", ISO8601DateFormatter().string(from: $0)) }))

            case .alarm:
                stepper("Hour", "hour", 7, 0...23)
                stepper("Minute", "minute", 30, 0...59)
                toggle("Enabled", "enabled", true)

            case .timeProgress:
                picker("Span", "span", "day",
                       options: [("day", "Today"), ("week", "This week"),
                                 ("month", "This month"), ("year", "This year")])

            case .stickyNote:
                field("Text", "text", "", width: 320)
                picker("Colour", "color", "#FFD60A",
                       options: [("#FFD60A", "Yellow"), ("#FF9F0A", "Orange"),
                                 ("#34C759", "Green"), ("#64D2FF", "Blue"),
                                 ("#BF5AF2", "Purple")])

            case .hydration:
                stepper("Daily goal (glasses)", "goal", 8, 1...20)
                stepper("Remind every (min)", "interval", 90, 15...480)

            case .weather:
                WeatherSettings()

            case .shortcut:
                HStack {
                    Text(L("Shortcut")).frame(width: 140, alignment: .leading)
                    ShortcutPicker(current: inst.string("name")) { set("name", $0) }
                }

            case .stripe, .paddle:
                RevenueSettings(kind: kind,
                                label: Binding(get: { inst.string("label", kind.title) },
                                               set: { set("label", $0) }))

            case .calendar:
                Button(L("Allow Calendar access")) { EventKitSource.shared.requestCalendarAccess() }
            case .reminders:
                Button(L("Allow Reminders access")) { EventKitSource.shared.requestRemindersAccess() }
            case .nowPlaying:
                Text(L("Controls Music and Spotify. macOS will ask for permission the first time."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            case .recentApps:
                stepper(L("How many"), "count", 3, 1...6)
                toggle(L("Hide apps already in this dock"), "hidePinned", true)
                Button(L("Clear recents")) { RecentAppsSource.shared.clear() }
                    .buttonStyle(.link)

            case .keepAwake:
                picker(L("Keep awake for"), "minutes", "0",
                       options: [("0", L("Until I turn it off")), ("15", L("15 minutes")),
                                 ("30", L("30 minutes")), ("60", L("1 hour")),
                                 ("120", L("2 hours"))])

            case .screenshot:
                toggle(L("Copy to clipboard instead of saving"), "clipboard", false)

            case .clipboard:
                stepper(L("Rows to show"), "rows", 2, 1...4)
                Text(L("History is kept in memory only and is never written to disk."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)

            case .volume, .diskSpace, .bluetoothBattery:
                Text(kind.blurb).font(.system(size: 11)).foregroundStyle(.secondary)

            case .stopwatch, .battery, .systemActivity, .networkActivity, .airDrop:
                Text(kind.blurb).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Field builders

    private func toggle(_ label: String, _ key: String, _ fallback: Bool) -> some View {
        Toggle(label, isOn: Binding(
            get: { inst.bool(key, fallback) },
            set: { set(key, $0 ? "true" : "false") }))
        .toggleStyle(.checkbox)
    }

    private func field(_ label: String, _ key: String, _ fallback: String,
                       width: CGFloat) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            TextField("", text: Binding(
                get: { inst.string(key, fallback) },
                set: { set(key, $0) }))
            .frame(width: width)
        }
    }

    private func stepper(_ label: String, _ key: String, _ fallback: Int,
                         _ range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            Stepper(value: Binding(
                get: { inst.int(key, fallback) },
                set: { set(key, String($0)) }), in: range) {
                    Text("\(inst.int(key, fallback))")
                        .font(.system(size: 12, design: .rounded))
                        .frame(width: 34, alignment: .leading)
                }
            .frame(width: 110)
        }
    }

    private func picker(_ label: String, _ key: String, _ fallback: String,
                        options: [(String, String)]) -> some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            Picker("", selection: Binding(
                get: { inst.string(key, fallback) },
                set: { set(key, $0) })) {
                    ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
                }
            .labelsHidden()
            .frame(width: 160)
        }
    }

    private func set(_ key: String, _ value: String) {
        store.update(profileID) { p in
            guard let i = p.items.firstIndex(where: { $0.id == item.id }) else { return }
            p.items[i].widget?.settings[key] = value
        }
    }
}

struct DatePickerRow: View {
    var label: String
    @Binding var value: Date
    var body: some View {
        HStack {
            Text(label).frame(width: 140, alignment: .leading)
            DatePicker("", selection: $value)
                .labelsHidden()
                .frame(width: 220)
        }
    }
}

struct WeatherSettings: View {
    @ObservedObject private var source = WeatherSource.shared
    @State private var place: String = WeatherSource.shared.manualPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Place")).frame(width: 140, alignment: .leading)
                TextField(L("Use my location"), text: $place)
                    .frame(width: 200)
                    .onSubmit { source.manualPlace = place }
                Button(L("Set")) { source.manualPlace = place }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
            Toggle(L("Fahrenheit"), isOn: Binding(
                get: { source.useFahrenheit }, set: { source.useFahrenheit = $0 }))
            .toggleStyle(.checkbox)
            Text(L("Weather comes from Open-Meteo. Leave the place blank to use Location Services."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct RevenueSettings: View {
    var kind: WidgetKind
    @Binding var label: String
    @State private var key: String = ""
    @State private var saved = false

    private var source: RevenueSource { RevenueSource.source(for: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Label")).frame(width: 140, alignment: .leading)
                TextField(kind.title, text: $label).frame(width: 200)
            }
            HStack {
                Text(L("API key")).frame(width: 140, alignment: .leading)
                SecureField(kind == .stripe ? "sk_live_…" : "Paddle API key", text: $key)
                    .frame(width: 240)
                Button(saved ? "Saved" : "Save") {
                    source.apiKey = key
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                }
                .disabled(key.isEmpty)
            }
            Text(L("Stored in your Keychain, never in the Dockly library file. Read-only keys are plenty."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if let err = source.snapshot.error {
                Text(err).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .onAppear { key = source.apiKey ?? "" }
    }
}
