import AppKit
import Combine
import CoreAudio
import IOKit.pwr_mgt

// MARK: - Volume and output device

/// System output volume, and which device it comes out of.
///
/// Reading and writing the level goes through Apple Events because that path
/// works for every kind of output device; the device list itself comes from
/// CoreAudio, which has no scripting equivalent.
final class VolumeSource: ObservableObject {
    static let shared = VolumeSource()

    struct Device: Identifiable, Hashable {
        var id: AudioDeviceID
        var name: String
    }

    @Published private(set) var level: Double = 0.5     // 0…1
    @Published private(set) var isMuted = false
    @Published private(set) var devices: [Device] = []
    @Published private(set) var currentDeviceName = ""

    private var timer: Timer?
    /// Set while the user is dragging, so polling does not fight the slider.
    private var settingUntil: Date = .distantPast

    private init() {
        refresh()
        timer = everySecond(2) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard Date() > settingUntil else { return }
        DispatchQueue.global(qos: .utility).async {
            let script = """
            set v to output volume of (get volume settings)
            set m to output muted of (get volume settings)
            return (v as text) & "," & (m as text)
            """
            var error: NSDictionary?
            let out = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let parts = (out?.stringValue ?? "").split(separator: ",").map(String.init)
            let devices = Self.outputDevices()
            let current = Self.defaultOutputDeviceName()

            DispatchQueue.main.async {
                if parts.count == 2, let v = Double(parts[0]) {
                    self.level = max(0, min(1, v / 100))
                    self.isMuted = parts[1] == "true"
                }
                if devices != self.devices { self.devices = devices }
                if current != self.currentDeviceName { self.currentDeviceName = current }
            }
        }
    }

    func setLevel(_ value: Double) {
        let clamped = max(0, min(1, value))
        level = clamped
        isMuted = clamped == 0
        settingUntil = Date().addingTimeInterval(1.5)
        let percent = Int(round(clamped * 100))
        run("set volume output volume \(percent)")
    }

    func toggleMute() {
        isMuted.toggle()
        settingUntil = Date().addingTimeInterval(1.5)
        run("set volume output muted \(isMuted)")
    }

    private func run(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    // MARK: CoreAudio

    func select(_ device: Device) {
        var id = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refresh()
    }

    private static func outputDevices() -> [Device] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return Device(id: id, name: name)
        }
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr
        else { return false }
        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).contains { $0.mNumberChannels > 0 }
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // CoreAudio hands back a +1 CFString, so it has to come through
        // Unmanaged rather than a plain CFString variable.
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func defaultOutputDeviceName() -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr else { return "" }
        return name(of: id) ?? ""
    }
}

// MARK: - Keep awake

/// Holds a power assertion so the Mac stays awake, the way Amphetamine or
/// `caffeinate` does.
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var isActive = false
    @Published private(set) var endsAt: Date?

    private var assertion: IOPMAssertionID = 0
    private var expiry: Timer?

    private init() {}

    /// `minutes` of zero means "until I turn it off".
    func activate(minutes: Int) {
        deactivate()
        var id: IOPMAssertionID = 0
        let reason = "Dockly Keep Awake" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &id)
        guard result == kIOReturnSuccess else { return }

        assertion = id
        isActive = true
        if minutes > 0 {
            let end = Date().addingTimeInterval(Double(minutes) * 60)
            endsAt = end
            expiry = everySecond(5) { [weak self] in
                guard let self, let endsAt = self.endsAt else { return }
                if Date() >= endsAt { self.deactivate() }
            }
        } else {
            endsAt = nil
        }
    }

    func deactivate() {
        expiry?.invalidate(); expiry = nil
        endsAt = nil
        guard isActive else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
        isActive = false
    }

    func toggle(minutes: Int) {
        isActive ? deactivate() : activate(minutes: minutes)
    }
}

// MARK: - Disk space

struct DiskUsage {
    var totalBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var name: String = "Macintosh HD"

    var usedFraction: Double {
        totalBytes > 0 ? Double(totalBytes - freeBytes) / Double(totalBytes) : 0
    }
    var freeString: String {
        ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)
    }
    var totalString: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

final class DiskSource: ObservableObject {
    static let shared = DiskSource()
    @Published private(set) var usage = DiskUsage()

    private var timer: Timer?

    private init() {
        refresh()
        timer = everySecond(60) { [weak self] in self?.refresh() }
    }

    func refresh() {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        var u = DiskUsage()
        u.totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        u.freeBytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        u.name = values.volumeName ?? "Macintosh HD"
        usage = u
    }
}

// MARK: - Bluetooth device batteries

struct BluetoothDevice: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var percent: Int
    var kind: String        // Headphones, Mouse, Keyboard…

    var symbol: String {
        let k = kind.lowercased()
        if k.contains("headphone") || k.contains("headset") { return "airpodspro" }
        if k.contains("mouse") { return "magicmouse.fill" }
        if k.contains("keyboard") { return "keyboard.fill" }
        if k.contains("speaker") { return "hifispeaker.fill" }
        if k.contains("gamepad") || k.contains("controller") { return "gamecontroller.fill" }
        return "dot.radiowaves.right"
    }
}

/// Battery levels for connected Bluetooth accessories.
///
/// There is no public framework for this, so Dockly reads the same report the
/// System Information app shows. It is slow, so it runs off the main thread on
/// a long interval.
final class BluetoothSource: ObservableObject {
    static let shared = BluetoothSource()

    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var isLoading = false

    private var timer: Timer?

    private init() {
        refresh()
        timer = everySecond(300) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async {
            let found = Self.read()
            DispatchQueue.main.async {
                self.isLoading = false
                guard found != self.devices else { return }
                self.devices = found
            }
        }
    }

    private static func read() -> [BluetoothDevice] {
        let json = NativeDockManager.run("/usr/sbin/system_profiler",
                                         ["SPBluetoothDataType", "-json"])
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var out: [BluetoothDevice] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, raw) in entry {
                    guard let info = raw as? [String: Any] else { continue }
                    let kind = (info["device_minorType"] as? String)
                        ?? (info["device_majorType"] as? String) ?? ""
                    // Accessories report one level; earbuds report three.
                    let keys = ["device_batteryLevelMain", "device_batteryLevel",
                                "device_batteryLevelLeft", "device_batteryLevelRight",
                                "device_batteryLevelCase"]
                    // The level comes back as "85%", "85" or a number,
                    // depending on the macOS version.
                    let levels = keys.compactMap { key -> Int? in
                        if let s = info[key] as? String {
                            return Int(s.replacingOccurrences(of: "%", with: "")
                                .trimmingCharacters(in: .whitespaces))
                        }
                        if let n = info[key] as? NSNumber { return n.intValue }
                        return nil
                    }
                    guard let lowest = levels.min() else { continue }
                    out.append(BluetoothDevice(name: name, percent: lowest, kind: kind))
                }
            }
        }
        return out.sorted { $0.percent < $1.percent }
    }
}

// MARK: - Screenshots

enum ScreenshotActions {
    enum Mode { case selection, window, screen }

    /// Runs the same capture the ⇧⌘ shortcuts run. Dockly hides itself first so
    /// it never ends up in the picture.
    static func capture(_ mode: Mode, toClipboard: Bool) {
        var args: [String] = []
        switch mode {
        case .selection: args.append("-i")
        case .window:    args.append(contentsOf: ["-i", "-w"])
        case .screen:    break
        }
        if toClipboard { args.append("-c") }
        if !toClipboard {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let desktop = FileManager.default.urls(for: .desktopDirectory,
                                                   in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            args.append(desktop.appendingPathComponent("Screenshot \(stamp).png").path)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = NativeDockManager.run("/usr/sbin/screencapture", args)
            }
        }
    }

    static func openScreenshotApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath:
            "/System/Applications/Utilities/Screenshot.app"))
    }
}
