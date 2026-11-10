import Foundation
import Combine
import EventKit
import CoreLocation
import AppKit

// MARK: - Calendar & Reminders (EventKit)

struct AgendaEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var isAllDay: Bool
    var colorHex: String
}

struct OpenReminder: Identifiable, Hashable {
    var id: String
    var title: String
    var due: Date?
    var listName: String
    var colorHex: String
}

final class EventKitSource: ObservableObject {
    static let shared = EventKitSource()

    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var reminders: [OpenReminder] = []
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var remindersAuthorized = false

    private let store = EKEventStore()
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store)
        timer = everySecond(120) { [weak self] in self?.refreshAll() }
    }

    @objc private func storeChanged() { refreshAll() }

    func requestCalendarAccess() {
        let done: (Bool, Error?) -> Void = { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.calendarAuthorized = ok
                self?.refreshEvents()
            }
        }
        if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: done) }
        else { store.requestAccess(to: .event, completion: done) }
    }

    func requestRemindersAccess() {
        let done: (Bool, Error?) -> Void = { [weak self] ok, _ in
            DispatchQueue.main.async {
                self?.remindersAuthorized = ok
                self?.refreshReminders()
            }
        }
        if #available(macOS 14.0, *) { store.requestFullAccessToReminders(completion: done) }
        else { store.requestAccess(to: .reminder, completion: done) }
    }

    func refreshAll() { refreshEvents(); refreshReminders() }

    func refreshEvents() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let granted: Bool
        if #available(macOS 14.0, *) { granted = status == .fullAccess }
        else { granted = status == .authorized }
        calendarAuthorized = granted
        guard granted else { events = []; return }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { ev in
                AgendaEvent(
                    id: ev.eventIdentifier ?? UUID().uuidString,
                    title: ev.title ?? "Event",
                    start: ev.startDate,
                    isAllDay: ev.isAllDay,
                    colorHex: ev.calendar?.color?.hexString ?? "#5B8CFF")
            }
        events = Array(found)
    }

    func refreshReminders() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        let granted: Bool
        if #available(macOS 14.0, *) { granted = status == .fullAccess }
        else { granted = status == .authorized }
        remindersAuthorized = granted
        guard granted else { reminders = []; return }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] found in
            let mapped = (found ?? [])
                .sorted { a, b in
                    let da = a.dueDateComponents?.date ?? .distantFuture
                    let db = b.dueDateComponents?.date ?? .distantFuture
                    return da < db
                }
                .prefix(10)
                .map { r in
                    OpenReminder(
                        id: r.calendarItemIdentifier,
                        title: r.title ?? "Reminder",
                        due: r.dueDateComponents?.date,
                        listName: r.calendar?.title ?? "Reminders",
                        colorHex: r.calendar?.color?.hexString ?? "#FF375F")
                }
            DispatchQueue.main.async { self?.reminders = Array(mapped) }
        }
    }

    func complete(reminderID: String) {
        guard let item = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
        refreshReminders()
    }
}

private extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

// MARK: - Weather (Open-Meteo, no API key)

struct WeatherSnapshot {
    var temperature: Double = 0
    var apparent: Double = 0
    var code: Int = 0
    var place: String = "—"
    var high: Double = 0
    var low: Double = 0
    var isDay: Bool = true
    var updated: Date = .distantPast

    var symbol: String { WeatherSnapshot.symbol(for: code, isDay: isDay) }
    var summary: String { WeatherSnapshot.summary(for: code) }

    static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0:        return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:     return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:        return "cloud.fill"
        case 45, 48:   return "cloud.fog.fill"
        case 51...57:  return "cloud.drizzle.fill"
        case 61...67:  return "cloud.rain.fill"
        case 71...77:  return "cloud.snow.fill"
        case 80...82:  return "cloud.heavyrain.fill"
        case 85, 86:   return "cloud.snow.fill"
        case 95...99:  return "cloud.bolt.rain.fill"
        default:       return "cloud.fill"
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0:        return L("Clear")
        case 1, 2:     return L("Partly cloudy")
        case 3:        return L("Overcast")
        case 45, 48:   return L("Fog")
        case 51...57:  return L("Drizzle")
        case 61...67:  return L("Rain")
        case 71...77:  return L("Snow")
        case 80...82:  return L("Showers")
        case 85, 86:   return L("Snow showers")
        case 95...99:  return L("Thunderstorms")
        default:       return L("—")
        }
    }
}

final class WeatherSource: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherSource()

    @Published private(set) var snapshot = WeatherSnapshot()
    @Published private(set) var isLoading = false
    /// Set when the user pins a place instead of using Location Services.
    @Published var manualPlace: String = UserDefaults.standard.string(forKey: "dockly.weather.place") ?? "" {
        didSet {
            UserDefaults.standard.set(manualPlace, forKey: "dockly.weather.place")
            refresh()
        }
    }
    @Published var useFahrenheit: Bool = UserDefaults.standard.bool(forKey: "dockly.weather.f") {
        didSet { UserDefaults.standard.set(useFahrenheit, forKey: "dockly.weather.f"); refresh() }
    }

    private let locations = CLLocationManager()
    private var timer: Timer?
    private var coordinate: CLLocationCoordinate2D?

    private override init() {
        super.init()
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyKilometer
        timer = everySecond(900) { [weak self] in self?.refresh() }
    }

    func start() {
        if manualPlace.isEmpty {
            locations.requestWhenInUseAuthorization()
            locations.startUpdatingLocation()
        }
        refresh()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        coordinate = l.coordinate
        m.stopUpdatingLocation()
        refresh()
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        NSLog("Dockly: location unavailable — \(error.localizedDescription)")
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        if !manualPlace.isEmpty {
            geocodeThenFetch(manualPlace)
        } else if let c = coordinate {
            fetch(latitude: c.latitude, longitude: c.longitude, place: nil)
        } else {
            isLoading = false
        }
    }

    private func geocodeThenFetch(_ place: String) {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place
        guard let url = URL(string:
            "https://geocoding-api.open-meteo.com/v1/search?name=\(q)&count=1&language=en&format=json")
        else { isLoading = false; return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double
            else { DispatchQueue.main.async { self?.isLoading = false }; return }
            let name = (first["name"] as? String) ?? place
            self?.fetch(latitude: lat, longitude: lon, place: name)
        }.resume()
    }

    private func fetch(latitude: Double, longitude: Double, place: String?) {
        let unit = useFahrenheit ? "fahrenheit" : "celsius"
        let spec = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)" +
            "&current=temperature_2m,apparent_temperature,weather_code,is_day" +
            "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1" +
            "&temperature_unit=\(unit)&timezone=auto"
        guard let url = URL(string: spec) else { isLoading = false; return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            defer { DispatchQueue.main.async { self?.isLoading = false } }
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = root["current"] as? [String: Any]
            else { return }

            var snap = WeatherSnapshot()
            snap.temperature = current["temperature_2m"] as? Double ?? 0
            snap.apparent = current["apparent_temperature"] as? Double ?? snap.temperature
            snap.code = current["weather_code"] as? Int ?? 0
            snap.isDay = (current["is_day"] as? Int ?? 1) == 1
            if let daily = root["daily"] as? [String: Any] {
                snap.high = (daily["temperature_2m_max"] as? [Double])?.first ?? snap.temperature
                snap.low = (daily["temperature_2m_min"] as? [Double])?.first ?? snap.temperature
            }
            snap.updated = Date()

            if let place {
                snap.place = place
                DispatchQueue.main.async { self?.snapshot = snap }
            } else {
                CLGeocoder().reverseGeocodeLocation(
                    CLLocation(latitude: latitude, longitude: longitude)) { marks, _ in
                    var s = snap
                    s.place = marks?.first?.locality ?? marks?.first?.name ?? "Here"
                    DispatchQueue.main.async { self?.snapshot = s }
                }
            }
        }.resume()
    }
}

// MARK: - Now Playing (Music / Spotify via Apple Events)

struct NowPlayingState {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var position: Double = 0
    var duration: Double = 0
    var isPlaying: Bool = false
    var app: String = ""
    var artwork: NSImage?

    var isEmpty: Bool { title.isEmpty }
}

final class NowPlayingSource: ObservableObject {
    static let shared = NowPlayingSource()
    @Published private(set) var state = NowPlayingState()

    private var timer: Timer?
    private var artworkKey: String = ""

    private init() {
        timer = everySecond(2) { [weak self] in self?.refresh() }
        refresh()
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            var next = NowPlayingState()
            if self.isRunning("com.spotify.client"), let s = self.query(spotifyScript, app: "Spotify") {
                next = s
            } else if self.isRunning("com.apple.Music"), let s = self.query(musicScript, app: "Music") {
                next = s
            }
            DispatchQueue.main.async {
                let key = next.title + next.artist
                if key != self.artworkKey {
                    self.artworkKey = key
                    self.state = next
                    self.loadArtwork(for: next)
                } else {
                    var merged = next
                    merged.artwork = self.state.artwork
                    self.state = merged
                }
            }
        }
    }

    private func query(_ source: String, app: String) -> NowPlayingState? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let out = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let raw = out.stringValue else { return nil }
        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count >= 5 else { return nil }
        var s = NowPlayingState()
        s.title = parts[0]
        s.artist = parts[1]
        s.album = parts[2]
        s.position = Double(parts[3]) ?? 0
        s.duration = Double(parts[4]) ?? 0
        s.isPlaying = parts.count > 5 ? parts[5] == "playing" : true
        s.app = app
        return s.title.isEmpty ? nil : s
    }

    private func loadArtwork(for s: NowPlayingState) {
        guard s.app == "Music", !s.title.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: musicArtworkScript) else { return }
            let out = script.executeAndReturnError(&error)
            guard error == nil, let data = out.data as Data?, !data.isEmpty,
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self.state.title == s.title else { return }
                self.state.artwork = image
            }
        }
    }

    // MARK: Transport

    func playPause() { control("playpause") }
    func next()      { control("next track") }
    func previous()  { control("previous track") }

    private func control(_ command: String) {
        let app = state.app.isEmpty ? "Music" : state.app
        let src = "tell application \"\(app)\" to \(command)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: src)?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
        }
    }
}

private let spotifyScript = """
tell application "Spotify"
  if player state is stopped then return ""
  set t to name of current track
  set a to artist of current track
  set al to album of current track
  set p to player position
  set d to (duration of current track) / 1000
  set st to (player state as text)
  return t & (ASCII character 31) & a & (ASCII character 31) & al & (ASCII character 31) & (p as text) & (ASCII character 31) & (d as text) & (ASCII character 31) & st
end tell
"""

private let musicScript = """
tell application "Music"
  if player state is stopped then return ""
  set t to name of current track
  set a to artist of current track
  set al to album of current track
  set p to player position
  set d to duration of current track
  set st to (player state as text)
  return t & (ASCII character 31) & a & (ASCII character 31) & al & (ASCII character 31) & (p as text) & (ASCII character 31) & (d as text) & (ASCII character 31) & st
end tell
"""

private let musicArtworkScript = """
tell application "Music"
  if player state is stopped then return missing value
  try
    return data of artwork 1 of current track
  on error
    return missing value
  end try
end tell
"""
