import Foundation
import Combine
import IOKit.ps
import Darwin

// MARK: - Battery

struct BatteryState {
    var percent: Int = 100
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var minutesRemaining: Int?
    var health: Int?
}

final class BatterySource: ObservableObject {
    static let shared = BatterySource()
    @Published private(set) var state = BatteryState()
    private var timer: Timer?

    private init() {
        refresh()
        timer = everySecond(20) { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for ps in list {
            guard let info = IOPSGetPowerSourceDescription(blob, ps)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            var s = BatteryState()
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            s.percent = max > 0 ? Int(round(Double(current) / Double(max) * 100)) : current
            s.isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            s.isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let toEmpty = info[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = info[kIOPSTimeToFullChargeKey] as? Int ?? -1
            let mins = s.isCharging ? toFull : toEmpty
            s.minutesRemaining = mins > 0 ? mins : nil
            state = s
            return
        }
    }
}

// MARK: - CPU + memory

struct ActivitySample {
    var cpu: Double = 0        // 0…1
    var memory: Double = 0     // 0…1
    var memoryUsedGB: Double = 0
    var memoryTotalGB: Double = 0
    var history: [Double] = []
}

final class ActivitySource: ObservableObject {
    static let shared = ActivitySource()
    @Published private(set) var sample = ActivitySample()

    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var timer: Timer?

    private init() {
        timer = everySecond(2) { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        var s = sample
        s.cpu = readCPU() ?? s.cpu
        let mem = readMemory()
        s.memory = mem.fraction
        s.memoryUsedGB = mem.usedGB
        s.memoryTotalGB = mem.totalGB
        s.history = (s.history + [s.cpu]).suffix(32)
        sample = s
    }

    private func readCPU() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = info.cpu_ticks.0, system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2, nice = info.cpu_ticks.3
        defer { previousTicks = (user, system, idle, nice) }
        guard let prev = previousTicks else { return nil }

        let du = Double(user &- prev.user)
        let ds = Double(system &- prev.system)
        let di = Double(idle &- prev.idle)
        let dn = Double(nice &- prev.nice)
        let total = du + ds + di + dn
        guard total > 0 else { return nil }
        return min(1, max(0, (du + ds + dn) / total))
    }

    private func readMemory() -> (fraction: Double, usedGB: Double, totalGB: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, total / 1_073_741_824) }

        let page = Double(vm_kernel_page_size)
        // "Used" the way Activity Monitor counts it: everything but free and
        // purgeable, plus compressed pages.
        let active = Double(stats.active_count) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let used = active + wired + compressed
        return (min(1, used / total), used / 1_073_741_824, total / 1_073_741_824)
    }
}

// MARK: - Network throughput

struct NetworkSample {
    var downBytesPerSecond: Int = 0
    var upBytesPerSecond: Int = 0
    var downHistory: [Double] = []
    var upHistory: [Double] = []
}

final class NetworkSource: ObservableObject {
    static let shared = NetworkSource()
    @Published private(set) var sample = NetworkSample()

    private var previous: (inBytes: UInt64, outBytes: UInt64, at: Date)?
    private var timer: Timer?

    private init() {
        timer = everySecond(1) { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        guard let totals = readTotals() else { return }
        let now = Date()
        defer { previous = (totals.inBytes, totals.outBytes, now) }
        guard let prev = previous else { return }

        let dt = now.timeIntervalSince(prev.at)
        guard dt > 0.1 else { return }
        let down = Int(Double(totals.inBytes &- prev.inBytes) / dt)
        let up = Int(Double(totals.outBytes &- prev.outBytes) / dt)

        var s = sample
        s.downBytesPerSecond = max(0, down)
        s.upBytesPerSecond = max(0, up)
        s.downHistory = (s.downHistory + [Double(max(0, down))]).suffix(40)
        s.upHistory = (s.upHistory + [Double(max(0, up))]).suffix(40)
        sample = s
    }

    private func readTotals() -> (inBytes: UInt64, outBytes: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = cur.pointee.ifa_data else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp") || name.hasPrefix("bridge")
            else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            inBytes += UInt64(data.ifi_ibytes)
            outBytes += UInt64(data.ifi_obytes)
        }
        return (inBytes, outBytes)
    }
}
