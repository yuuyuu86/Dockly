import SwiftUI
import AppKit

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        } else {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }

    static let docklyPalette: [String] = [
        "#5B8CFF", "#34C759", "#FF9F0A", "#FF375F", "#BF5AF2",
        "#64D2FF", "#FFD60A", "#FF6B35", "#30D158", "#8E8E93",
    ]
}

enum KeyCodeNames {
    private static let map: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7",
        28: "8", 29: "0", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
        40: "K", 45: "N", 46: "M",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",",
        44: "/", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    static func name(for code: UInt32) -> String { map[code] ?? "Key\(code)" }
}

extension NSImage {
    /// A square, crisply-resized copy — dock icons are drawn a lot, so this
    /// keeps the work off the render pass.
    func resized(to side: CGFloat) -> NSImage {
        let target = NSSize(width: side, height: side)
        let img = NSImage(size: target)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target),
             from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        return img
    }
}

extension TimeInterval {
    var clockString: String {
        let t = max(0, Int(rounded()))
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
    var preciseString: String {
        let t = max(0, self)
        let m = Int(t) / 60, s = Int(t) % 60, cs = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}

extension Int {
    var byteRateString: String {
        let b = Double(self)
        if b < 1024 { return "\(self) B/s" }
        if b < 1024 * 1024 { return String(format: "%.0f KB/s", b / 1024) }
        return String(format: "%.1f MB/s", b / 1024 / 1024)
    }
}

/// Small helper so `Timer` work always lands on the main actor.
func everySecond(_ interval: TimeInterval = 1, _ body: @escaping () -> Void) -> Timer {
    let t = Timer(timeInterval: interval, repeats: true) { _ in
        DispatchQueue.main.async(execute: body)
    }
    RunLoop.main.add(t, forMode: .common)
    return t
}
