import SwiftUI

// MARK: - Clock

struct ClockWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var use24h: Bool { context.instance.bool("h24", true) }
    private var showSeconds: Bool { context.instance.bool("seconds", false) }
    private var showDate: Bool { context.instance.bool("date", true) }

    var body: some View {
        WidgetPlate(context: context) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetValue(text: timeText, context: context, size: showDate ? 16 : 19)
                if showDate {
                    WidgetCaption(text: dateText, context: context)
                }
            }
        }
        .help(L("Clock"))
    }

    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = use24h
            ? (showSeconds ? "HH:mm:ss" : "HH:mm")
            : (showSeconds ? "h:mm:ss a" : "h:mm a")
        return f.string(from: engine.tick)
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: engine.tick)
    }
}

// MARK: - World Clock

struct WorldClockWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var zones: [String] {
        let raw = context.instance.string("zones", "Europe/London,America/New_York")
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(12)) {
                ForEach(zones.prefix(3), id: \.self) { zone in
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetValue(text: time(in: zone), context: context, size: 14)
                        WidgetCaption(text: label(zone), context: context)
                    }
                }
            }
        }
        .help(L("World Clock"))
    }

    private func time(in zone: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: zone) ?? .current
        f.dateFormat = context.instance.bool("h24", true) ? "HH:mm" : "h:mm a"
        return f.string(from: engine.tick)
    }

    private func label(_ zone: String) -> String {
        zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone
    }
}

// MARK: - Stopwatch

struct StopwatchWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    var body: some View {
        let s = engine.stopwatch(context.id)
        WidgetPlate(context: context, tint: s.isRunning ? context.accent : nil) {
            HStack(spacing: context.pt(7)) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: s.current.preciseString, context: context, size: 15)
                    WidgetCaption(text: s.laps.isEmpty ? L("Stopwatch") : L("Lap %d", s.laps.count),
                                  context: context)
                }
                WidgetButton(symbol: s.isRunning ? "pause.fill" : "play.fill",
                             context: context, prominent: true) {
                    engine.toggleStopwatch(context.id)
                }
            }
        }
        .contextMenu {
            Button(L("Lap")) { engine.lapStopwatch(context.id) }
            Button(L("Reset")) { engine.resetStopwatch(context.id) }
        }
        .help(L("Stopwatch"))
    }
}

// MARK: - Focus Timer

struct FocusTimerWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var focusMin: Int { context.instance.int("focus", 25) }
    private var shortMin: Int { context.instance.int("short", 5) }
    private var longMin: Int { context.instance.int("long", 15) }

    var body: some View {
        let s = engine.focus(context.id, defaults: (focusMin, shortMin, longMin))
        let color = s.phase == .focus ? context.accent : Color(hex: "#34C759")!

        WidgetPlate(context: context, tint: s.isRunning ? color : nil) {
            HStack(spacing: context.pt(8)) {
                ZStack {
                    RingGauge(progress: s.progress, color: color,
                              lineWidth: context.pt(3))
                    Image(systemName: s.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: context.pt(8), weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: context.pt(26), height: context.pt(26))
                .contentShape(Circle())
                .onTapGesture { engine.toggleFocus(context.id) }

                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: s.left.clockString, context: context, size: 15)
                    WidgetCaption(text: s.phase.title, context: context)
                }
            }
        }
        .contextMenu {
            Button(L("Skip to next phase")) {
                engine.skipFocusPhase(context.id, focusMin: focusMin,
                                      shortMin: shortMin, longMin: longMin)
            }
            Button(L("Reset")) { engine.resetFocus(context.id, minutes: focusMin) }
            Divider()
            Text(L("%d rounds today",
                 engine.focus(context.id, defaults: (focusMin, shortMin, longMin)).completedRounds))
        }
        .help(L("Focus Timer"))
    }
}

// MARK: - Countdown

struct CountdownWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var target: Date {
        if let raw = context.instance["target"], let t = ISO8601DateFormatter().date(from: raw) {
            return t
        }
        return Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }
    private var title: String { context.instance.string("title", L("Countdown")) }

    var body: some View {
        WidgetPlate(context: context) {
            HStack(spacing: context.pt(8)) {
                Image(systemName: "hourglass")
                    .font(.system(size: context.pt(13), weight: .semibold))
                    .foregroundStyle(context.accent)
                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: remainingText, context: context, size: 15)
                    WidgetCaption(text: title, context: context)
                }
            }
        }
        .help(L("Counting down to %@", target.formatted(date: .abbreviated, time: .shortened)))
    }

    private var remainingText: String {
        let left = target.timeIntervalSince(engine.tick)
        if left <= 0 { return L("Now") }
        let days = Int(left) / 86400
        if days >= 1 { return L("%1$dd %2$dh", days, Int(left) % 86400 / 3600) }
        return left.clockString
    }
}

// MARK: - Alarm

struct AlarmWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared
    @ObservedObject private var store = DocklyStore.shared

    private var hour: Int { context.instance.int("hour", 7) }
    private var minute: Int { context.instance.int("minute", 30) }
    private var enabled: Bool { context.instance.bool("enabled", true) }

    var body: some View {
        WidgetPlate(context: context, tint: enabled ? context.accent : nil) {
            HStack(spacing: context.pt(8)) {
                Image(systemName: enabled ? "alarm.fill" : "alarm")
                    .font(.system(size: context.pt(13), weight: .semibold))
                    .foregroundStyle(enabled ? context.accent : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 0) {
                    WidgetValue(text: String(format: "%02d:%02d", hour, minute),
                                context: context, size: 15)
                    WidgetCaption(text: enabled ? L("Alarm") : L("Off"), context: context)
                }
            }
        }
        .onTapGesture {
            store.setWidgetSetting(context.id, "enabled", enabled ? "false" : "true")
        }
        .onChange(of: engine.tick) { _ in
            engine.considerAlarm(id: context.id, hour: hour, minute: minute, enabled: enabled)
        }
        .help(enabled ? L("Alarm — click to turn off") : L("Alarm — click to turn on"))
    }
}

// MARK: - Time Progress

struct TimeProgressWidget: View {
    var context: WidgetContext
    @ObservedObject private var engine = TimerEngine.shared

    private var span: String { context.instance.string("span", "day") }

    var body: some View {
        let p = progress
        WidgetPlate(context: context) {
            VStack(alignment: .leading, spacing: context.pt(3)) {
                HStack(spacing: context.pt(5)) {
                    WidgetValue(text: "\(Int(round(p * 100)))%", context: context, size: 14)
                        WidgetCaption(text: spanLabel, context: context)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(context.accent)
                            .frame(width: max(2, geo.size.width * p))
                    }
                }
                .frame(width: context.pt(74), height: context.pt(5))
            }
        }
        .help(L("%@ progress", spanLabel))
    }

    private var spanLabel: String {
        switch span {
        case "week":  return L("This week")
        case "month": return L("This month")
        case "year":  return L("This year")
        default:      return L("Today")
        }
    }

    private var progress: Double {
        let cal = Calendar.current
        let now = engine.tick
        let unit: Calendar.Component
        switch span {
        case "week":  unit = .weekOfYear
        case "month": unit = .month
        case "year":  unit = .year
        default:      unit = .day
        }
        guard let interval = cal.dateInterval(of: unit, for: now) else { return 0 }
        let total = interval.duration
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(interval.start) / total))
    }
}
