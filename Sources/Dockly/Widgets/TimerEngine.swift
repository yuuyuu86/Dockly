import Foundation
import Combine
import AppKit
import UserNotifications

/// Runtime state for the time-based widgets. Widgets are value types that get
/// rebuilt constantly, so anything that ticks lives here, keyed by item id.
final class TimerEngine: ObservableObject {
    static let shared = TimerEngine()

    // MARK: Stopwatch

    struct Stopwatch: Codable {
        var elapsed: TimeInterval = 0
        var startedAt: Date?
        var laps: [TimeInterval] = []
        var isRunning: Bool { startedAt != nil }
        var current: TimeInterval {
            elapsed + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
        }
    }

    // MARK: Focus timer (pomodoro)

    enum FocusPhase: String, Codable { case focus, shortBreak, longBreak
        var title: String {
            switch self {
            case .focus: return L("Focus")
            case .shortBreak: return L("Break")
            case .longBreak: return L("Long break")
            }
        }
    }

    struct FocusSession: Codable {
        var phase: FocusPhase = .focus
        var remaining: TimeInterval = 25 * 60
        var total: TimeInterval = 25 * 60
        var endsAt: Date?
        var completedRounds: Int = 0
        var isRunning: Bool { endsAt != nil }
        var left: TimeInterval {
            endsAt.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
        }
        var progress: Double { total > 0 ? 1 - (left / total) : 0 }
    }

    // MARK: Countdown

    struct Countdown: Codable {
        var target: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        var title: String = "Countdown"
    }

    // MARK: Hydration

    struct Hydration: Codable {
        var glasses: Int = 0
        var goal: Int = 8
        var intervalMinutes: Int = 90
        var lastDrink: Date?
        var day: Int = TimerEngine.dayStamp()
        var nextDue: Date? {
            guard let lastDrink else { return nil }
            return lastDrink.addingTimeInterval(Double(intervalMinutes) * 60)
        }
    }

    @Published var stopwatches: [UUID: Stopwatch] = [:] { didSet { scheduleSave() } }
    @Published var focusSessions: [UUID: FocusSession] = [:] { didSet { scheduleSave() } }
    @Published var countdowns: [UUID: Countdown] = [:] { didSet { scheduleSave() } }
    @Published var hydration: [UUID: Hydration] = [:] { didSet { scheduleSave() } }
    /// Drives per-second redraws for everything above.
    @Published private(set) var tick: Date = Date()

    private var timer: Timer?
    private var firedAlarms: Set<String> = []
    private var saveWork: DispatchWorkItem?

    /// Everything the time widgets need to remember between launches. Kept
    /// apart from the library so a setup can be exported without dragging a
    /// half-finished pomodoro along with it.
    private struct Persisted: Codable {
        var stopwatches: [UUID: Stopwatch] = [:]
        var focusSessions: [UUID: FocusSession] = [:]
        var countdowns: [UUID: Countdown] = [:]
        var hydration: [UUID: Hydration] = [:]
    }

    private static var stateURL: URL {
        DocklyStore.supportDirectory.appendingPathComponent("widget-state.json")
    }

    /// yyyyMMdd, so hydration rolls over at local midnight.
    static func dayStamp(_ date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private init() {
        restore()
        timer = everySecond(0.2) { [weak self] in self?.beat() }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Persistence

    private func restore() {
        guard let data = try? Data(contentsOf: Self.stateURL),
              let saved = try? JSONDecoder.dockly.decode(Persisted.self, from: data)
        else { return }
        stopwatches = saved.stopwatches
        countdowns = saved.countdowns
        hydration = saved.hydration

        // A timer that was counting down while the app was closed should not
        // silently "finish" on the next launch — bring it back paused, with
        // whatever time was left.
        focusSessions = saved.focusSessions.mapValues { session in
            var s = session
            if let endsAt = s.endsAt {
                s.remaining = max(0, endsAt.timeIntervalSinceNow)
                s.endsAt = nil
            }
            return s
        }
        // Same for a running stopwatch: bank the time, leave it stopped.
        stopwatches = stopwatches.mapValues { watch in
            var w = watch
            if let started = w.startedAt {
                w.elapsed += Date().timeIntervalSince(started)
                w.startedAt = nil
            }
            return w
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        let snapshot = Persisted(stopwatches: stopwatches, focusSessions: focusSessions,
                                 countdowns: countdowns, hydration: hydration)
        guard let data = try? JSONEncoder.dockly.encode(snapshot) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }

    private func beat() {
        tick = Date()
        checkFocusSessions()
        rolloverHydration()
    }

    // MARK: Stopwatch API

    func stopwatch(_ id: UUID) -> Stopwatch { stopwatches[id] ?? Stopwatch() }

    func toggleStopwatch(_ id: UUID) {
        var s = stopwatch(id)
        if let started = s.startedAt {
            s.elapsed += Date().timeIntervalSince(started)
            s.startedAt = nil
        } else {
            s.startedAt = Date()
        }
        stopwatches[id] = s
    }

    func lapStopwatch(_ id: UUID) {
        var s = stopwatch(id)
        guard s.isRunning else { return }
        s.laps.append(s.current)
        stopwatches[id] = s
    }

    func resetStopwatch(_ id: UUID) { stopwatches[id] = Stopwatch() }

    // MARK: Focus timer API

    func focus(_ id: UUID, defaults: (focus: Int, short: Int, long: Int)) -> FocusSession {
        if let existing = focusSessions[id] { return existing }
        var s = FocusSession()
        s.total = Double(defaults.focus) * 60
        s.remaining = s.total
        focusSessions[id] = s
        return s
    }

    func toggleFocus(_ id: UUID) {
        guard var s = focusSessions[id] else { return }
        if let endsAt = s.endsAt {
            s.remaining = max(0, endsAt.timeIntervalSinceNow)
            s.endsAt = nil
        } else {
            s.endsAt = Date().addingTimeInterval(s.remaining)
        }
        focusSessions[id] = s
    }

    func resetFocus(_ id: UUID, minutes: Int) {
        var s = focusSessions[id] ?? FocusSession()
        s.phase = .focus
        s.total = Double(minutes) * 60
        s.remaining = s.total
        s.endsAt = nil
        focusSessions[id] = s
    }

    func skipFocusPhase(_ id: UUID, focusMin: Int, shortMin: Int, longMin: Int) {
        guard var s = focusSessions[id] else { return }
        advance(&s, focusMin: focusMin, shortMin: shortMin, longMin: longMin)
        focusSessions[id] = s
    }

    private func advance(_ s: inout FocusSession, focusMin: Int, shortMin: Int, longMin: Int) {
        switch s.phase {
        case .focus:
            s.completedRounds += 1
            s.phase = s.completedRounds % 4 == 0 ? .longBreak : .shortBreak
            s.total = Double(s.phase == .longBreak ? longMin : shortMin) * 60
        case .shortBreak, .longBreak:
            s.phase = .focus
            s.total = Double(focusMin) * 60
        }
        s.remaining = s.total
        s.endsAt = nil
    }

    private func checkFocusSessions() {
        for (id, s) in focusSessions where s.isRunning && s.left <= 0 {
            var next = s
            notify(title: "\(s.phase.title) finished",
                   body: s.phase == .focus ? "Time for a break." : "Back to it.")
            advance(&next, focusMin: Int(s.total / 60), shortMin: 5, longMin: 15)
            focusSessions[id] = next
        }
    }

    // MARK: Countdown API

    func countdown(_ id: UUID, target: Date, title: String) -> Countdown {
        if let existing = countdowns[id] { return existing }
        let c = Countdown(target: target, title: title)
        countdowns[id] = c
        return c
    }

    // MARK: Alarm API

    /// Called every beat by the alarm widget so a missed second never skips it.
    func considerAlarm(id: UUID, hour: Int, minute: Int, enabled: Bool) {
        guard enabled else { return }
        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .year, .month, .day], from: now)
        guard c.hour == hour, c.minute == minute else { return }
        let key = "\(id)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(hour)-\(minute)"
        guard !firedAlarms.contains(key) else { return }
        firedAlarms.insert(key)
        notify(title: "Alarm", body: String(format: "It's %02d:%02d.", hour, minute))
        NSSound(named: "Glass")?.play()
    }

    // MARK: Hydration API

    func hydrationState(_ id: UUID, goal: Int, interval: Int) -> Hydration {
        if var existing = hydration[id] {
            existing.goal = goal
            existing.intervalMinutes = interval
            return existing
        }
        var h = Hydration()
        h.goal = goal
        h.intervalMinutes = interval
        hydration[id] = h
        return h
    }

    func drink(_ id: UUID) {
        var h = hydration[id] ?? Hydration()
        h.glasses += 1
        h.lastDrink = Date()
        hydration[id] = h
    }

    func resetHydration(_ id: UUID) {
        var h = hydration[id] ?? Hydration()
        h.glasses = 0
        h.lastDrink = nil
        hydration[id] = h
    }

    private func rolloverHydration() {
        let today = TimerEngine.dayStamp()
        for (id, h) in hydration where h.day != today {
            var fresh = h
            fresh.day = today
            fresh.glasses = 0
            fresh.lastDrink = nil
            hydration[id] = fresh
        }
    }

    // MARK: Notifications

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
