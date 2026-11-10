import SwiftUI
import AppKit

// MARK: - Calendar

struct CalendarWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = EventKitSource.shared
    @ObservedObject private var engine = TimerEngine.shared

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(9)) {
                dateBlock
                if source.calendarAuthorized {
                    if source.events.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            WidgetValue(text: L("Nothing next"), context: context, size: 12)
                            WidgetCaption(text: L("Clear schedule"), context: context)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: context.pt(2)) {
                            ForEach(source.events.prefix(3)) { ev in
                                HStack(spacing: context.pt(5)) {
                                    Circle()
                                        .fill(Color(hex: ev.colorHex) ?? context.accent)
                                        .frame(width: context.pt(5), height: context.pt(5))
                                    Text(ev.title)
                                        .font(.system(size: context.pt(10), weight: .medium))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                    Spacer(minLength: context.pt(4))
                                    Text(ev.isAllDay ? L("All day") : timeString(ev.start))
                                        .font(.system(size: context.pt(9), weight: .semibold,
                                                      design: .rounded))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                } else {
                    Button(L("Allow Calendar")) { source.requestCalendarAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: context.pt(10), weight: .semibold))
                        .foregroundStyle(context.accent)
                }
            }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(string: "ical://")!) }
        .onAppear { if !source.calendarAuthorized { source.refreshEvents() } }
        .help(L("Calendar — double-click to open"))
    }

    private var dateBlock: some View {
        VStack(spacing: -context.pt(2)) {
            Text(weekday.uppercased())
                .font(.system(size: context.pt(8), weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: "#FF375F") ?? .red)
            Text(dayNumber)
                .font(.system(size: context.pt(17), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: context.pt(28))
    }

    private var weekday: String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: engine.tick)
    }
    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: engine.tick)
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d)
    }
}

// MARK: - Reminders

struct RemindersWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = EventKitSource.shared

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(9)) {
                ZStack {
                    Circle().fill(Color(hex: "#FF375F")!.opacity(0.22))
                    Text("\(source.reminders.count)")
                        .font(.system(size: context.pt(13), weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FF375F")!)
                }
                .frame(width: context.pt(26), height: context.pt(26))

                if source.remindersAuthorized {
                    VStack(alignment: .leading, spacing: context.pt(2)) {
                        if source.reminders.isEmpty {
                            WidgetValue(text: L("All clear"), context: context, size: 12)
                        } else {
                            ForEach(source.reminders.prefix(3)) { r in
                                HStack(spacing: context.pt(5)) {
                                    Button {
                                        source.complete(reminderID: r.id)
                                    } label: {
                                        Image(systemName: "circle")
                                            .font(.system(size: context.pt(9), weight: .bold))
                                            .foregroundStyle(Color(hex: r.colorHex) ?? .pink)
                                    }
                                    .buttonStyle(.plain)
                                    Text(r.title)
                                        .font(.system(size: context.pt(10), weight: .medium))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .lineLimit(1)
                                                    }
                            }
                        }
                    }
                } else {
                    Button(L("Allow Reminders")) { source.requestRemindersAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: context.pt(10), weight: .semibold))
                        .foregroundStyle(context.accent)
                }
            }
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!) }
        .onAppear { source.refreshReminders() }
        .help(L("Reminders — double-click to open"))
    }
}

// MARK: - Now Playing

struct NowPlayingWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = NowPlayingSource.shared

    var body: some View {
        let s = source.state
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                artwork(s)
                if s.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetValue(text: L("Nothing playing"), context: context, size: 12)
                        WidgetCaption(text: L("Music · Spotify"), context: context)
                    }
                } else {
                    VStack(alignment: .leading, spacing: context.pt(2)) {
                        Text(s.title)
                            .font(.system(size: context.pt(11), weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(s.artist)
                            .font(.system(size: context.pt(9), weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        progressBar(s)
                    }
                }
                HStack(spacing: context.pt(2)) {
                    WidgetButton(symbol: "backward.fill", context: context) { source.previous() }
                    WidgetButton(symbol: s.isPlaying ? "pause.fill" : "play.fill",
                                 context: context, prominent: true) { source.playPause() }
                    WidgetButton(symbol: "forward.fill", context: context) { source.next() }
                }
            }
        }
        .help(L("Now Playing"))
    }

    @ViewBuilder
    private func artwork(_ s: NowPlayingState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: context.pt(6), style: .continuous)
                .fill(Color.white.opacity(0.10))
            if let art = s.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: context.pt(6), style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: context.pt(12), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: context.pt(28), height: context.pt(28))
    }

    @ViewBuilder
    private func progressBar(_ s: NowPlayingState) -> some View {
        let p = s.duration > 0 ? min(1, max(0, s.position / s.duration)) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(Color.white.opacity(0.75))
                    .frame(width: max(1, geo.size.width * p))
            }
        }
        .frame(width: context.pt(104), height: context.pt(2.5))
    }
}

// MARK: - Sticky Note

struct StickyNoteWidget: View {
    var context: WidgetContext
    @ObservedObject private var store = DocklyStore.shared
    @State private var draft: String = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var saved: String { context.instance.string("text", "") }
    private var paper: Color { Color(hex: context.instance.string("color", "#FFD60A")) ?? .yellow }

    var body: some View {
        WidgetPlate(context: context, tint: paper) {
            Group {
                if editing {
                    TextEditor(text: $draft)
                        .font(.system(size: context.pt(10), weight: .medium))
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onChange(of: draft) { new in
                            store.setWidgetSetting(context.id, "text", new)
                        }
                        .onSubmit { editing = false }
                } else {
                    Text(saved.isEmpty ? L("Click to write a note…") : saved)
                        .font(.system(size: context.pt(10),
                                      weight: saved.isEmpty ? .regular : .medium))
                        .foregroundStyle(.white.opacity(saved.isEmpty ? 0.45 : 0.95))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .onTapGesture {
            draft = saved
            editing = true
            focused = true
        }
        .contextMenu {
            Button(L("Clear")) { store.setWidgetSetting(context.id, "text", ""); draft = "" }
            Button(L("Done editing")) { editing = false }
            Divider()
            ForEach(["#FFD60A", "#FF9F0A", "#34C759", "#64D2FF", "#BF5AF2"], id: \.self) { hex in
                Button(hex) { store.setWidgetSetting(context.id, "color", hex) }
            }
        }
        .help(L("Sticky Note"))
    }
}

// MARK: - Hydration

struct HydrationWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var goal: Int { context.instance.int("goal", 8) }
    private var interval: Int { context.instance.int("interval", 90) }

    var body: some View {
        let h = engine.hydrationState(context.id, goal: goal, interval: interval)
        let progress = goal > 0 ? Double(h.glasses) / Double(goal) : 0
        let water = Color(hex: "#64D2FF") ?? .cyan

        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    RingGauge(progress: progress, color: water, lineWidth: context.pt(3))
                    Image(systemName: "drop.fill")
                        .font(.system(size: context.pt(9), weight: .bold))
                        .foregroundStyle(water)
                }
                .frame(width: context.pt(26), height: context.pt(26))

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: "\(h.glasses)/\(goal)", context: context, size: 14)
                    WidgetCaption(text: nextText(h), context: context)
                }
            }
        }
        .onTapGesture { engine.drink(context.id) }
        .contextMenu {
            Button(L("Reset today")) { engine.resetHydration(context.id) }
        }
        .help(L("Hydration — click when you drink"))
    }

    private func nextText(_ h: TimerEngine.Hydration) -> String {
        guard let next = h.nextDue else { return L("Next drink") }
        let left = next.timeIntervalSince(engine.tick)
        if left <= 0 { return L("Time to drink") }
        return L("Next in %dm", Int(left / 60) + 1)
    }
}

// MARK: - Weather

struct WeatherWidget: View {
    var context: WidgetContext
    @ObservedObject private var source = WeatherSource.shared

    private var loaded: Bool { source.snapshot.updated != .distantPast }

    var body: some View {
        let s = source.snapshot
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                Image(systemName: loaded ? s.symbol : "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: context.pt(16)))
                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: loaded ? "\(Int(round(s.temperature)))°" : "--°",
                                context: context, size: 16)
                    WidgetCaption(text: loaded ? s.place : L("Weather"), context: context)
                }
            }
        }
        .onAppear { source.start() }
        .contextMenu {
            Button(L("Refresh")) { source.refresh() }
            Toggle(L("Fahrenheit"), isOn: Binding(
                get: { source.useFahrenheit },
                set: { source.useFahrenheit = $0 }))
        }
        .help(s.summary.isEmpty ? L("Weather")
              : L("%1$@ · H %2$d° L %3$d°", s.summary,
                  Int(round(s.high)), Int(round(s.low))))
    }
}
