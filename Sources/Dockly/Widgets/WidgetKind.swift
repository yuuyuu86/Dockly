import SwiftUI

enum WidgetCategory: String, Codable, CaseIterable, Identifiable {
    case timeAndFocus, everyday, yourMac, business
    var id: String { rawValue }
    var title: String {
        switch self {
        case .timeAndFocus: return L("Time & focus")
        case .everyday:     return L("Everyday")
        case .yourMac:      return L("Your Mac")
        case .business:     return L("Business")
        }
    }
}

/// The twenty widgets that ship with Dockly.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    // Time & focus
    case clock, worldClock, stopwatch, focusTimer, countdown, alarm, timeProgress
    // Everyday
    case calendar, reminders, nowPlaying, stickyNote, hydration, weather
    // Your Mac
    case battery, systemActivity, networkActivity, airDrop, shortcut, recentApps
    case volume, keepAwake, diskSpace, bluetoothBattery, screenshot, clipboard
    // Business
    case stripe, paddle

    var id: String { rawValue }

    var category: WidgetCategory {
        switch self {
        case .clock, .worldClock, .stopwatch, .focusTimer, .countdown, .alarm, .timeProgress:
            return .timeAndFocus
        case .calendar, .reminders, .nowPlaying, .stickyNote, .hydration, .weather:
            return .everyday
        case .battery, .systemActivity, .networkActivity, .airDrop, .shortcut, .recentApps,
             .volume, .keepAwake, .diskSpace, .bluetoothBattery, .screenshot, .clipboard:
            return .yourMac
        case .stripe, .paddle:
            return .business
        }
    }

    var title: String {
        switch self {
        case .clock:           return L("Clock")
        case .worldClock:      return L("World Clock")
        case .stopwatch:       return L("Stopwatch")
        case .focusTimer:      return L("Focus Timer")
        case .countdown:       return L("Countdown")
        case .alarm:           return L("Alarm")
        case .timeProgress:    return L("Time Progress")
        case .calendar:        return L("Calendar")
        case .reminders:       return L("Reminders")
        case .nowPlaying:      return L("Now Playing")
        case .stickyNote:      return L("Sticky Note")
        case .hydration:       return L("Hydration")
        case .weather:         return L("Weather")
        case .battery:         return L("Battery")
        case .systemActivity:  return L("System Activity")
        case .networkActivity: return L("Network Activity")
        case .airDrop:         return L("AirDrop")
        case .shortcut:        return L("Shortcut")
        case .recentApps:      return L("Recent Apps")
        case .volume:          return L("Volume")
        case .keepAwake:       return L("Keep Awake")
        case .diskSpace:       return L("Disk Space")
        case .bluetoothBattery: return L("Bluetooth Battery")
        case .screenshot:      return L("Screenshot")
        case .clipboard:       return L("Clipboard")
        case .stripe:          return L("Stripe")
        case .paddle:          return L("Paddle")
        }
    }

    var blurb: String {
        switch self {
        case .clock:           return L("The time, right where you look.")
        case .worldClock:      return L("Another city, another hour.")
        case .stopwatch:       return L("Start, lap, stop.")
        case .focusTimer:      return L("Pomodoro-style focus sessions.")
        case .countdown:       return L("Count down to the thing that matters.")
        case .alarm:           return L("A nudge at the time you pick.")
        case .timeProgress:    return L("How much of the day, week, or year is left.")
        case .calendar:        return L("Today's date and your next meetings.")
        case .reminders:       return L("Your open reminders, one tap away.")
        case .nowPlaying:      return L("What's playing, with controls.")
        case .stickyNote:      return L("A thought you don't want to lose.")
        case .hydration:       return L("A gentle reminder to drink water.")
        case .weather:         return L("Right now, outside.")
        case .battery:         return L("Charge, and how fast it's going.")
        case .systemActivity:  return L("CPU and memory at a glance.")
        case .networkActivity: return L("Up and down, live.")
        case .airDrop:         return L("Drop files here to send them.")
        case .shortcut:        return L("Run a macOS Shortcut in one click.")
        case .recentApps:      return L("The apps you switched to most recently.")
        case .volume:          return L("Set the volume and pick an output.")
        case .keepAwake:       return L("Stop the Mac going to sleep.")
        case .diskSpace:       return L("How much room is left.")
        case .bluetoothBattery: return L("Battery levels for your accessories.")
        case .screenshot:      return L("Grab a selection, a window, or the screen.")
        case .clipboard:       return L("The last few things you copied.")
        case .stripe:          return L("Stripe revenue while you work.")
        case .paddle:          return L("Paddle revenue while you work.")
        }
    }

    var symbol: String {
        switch self {
        case .clock:           return "clock"
        case .worldClock:      return "globe"
        case .stopwatch:       return "stopwatch"
        case .focusTimer:      return "timer"
        case .countdown:       return "hourglass"
        case .alarm:           return "alarm"
        case .timeProgress:    return "chart.bar.fill"
        case .calendar:        return "calendar"
        case .reminders:       return "checklist"
        case .nowPlaying:      return "music.note"
        case .stickyNote:      return "note.text"
        case .hydration:       return "drop.fill"
        case .weather:         return "cloud.sun.fill"
        case .battery:         return "battery.75"
        case .systemActivity:  return "cpu"
        case .networkActivity: return "arrow.up.arrow.down"
        case .airDrop:         return "wifi"
        case .shortcut:        return "square.stack.3d.up.fill"
        case .recentApps:      return "clock.arrow.circlepath"
        case .volume:          return "speaker.wave.2.fill"
        case .keepAwake:       return "cup.and.saucer.fill"
        case .diskSpace:       return "internaldrive.fill"
        case .bluetoothBattery: return "dot.radiowaves.right"
        case .screenshot:      return "camera.viewfinder"
        case .clipboard:       return "doc.on.clipboard"
        case .stripe:          return "creditcard.fill"
        case .paddle:          return "chart.line.uptrend.xyaxis"
        }
    }

}
