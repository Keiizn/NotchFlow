import Foundation
import Darwin

/// Statistiques système (processeur, mémoire, disque), échantillonnées
/// uniquement quand l'onglet Système est affiché.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var diskFree: Double = 0
    @Published private(set) var diskTotal: Double = 0
    @Published private(set) var uptime: TimeInterval = 0
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal

    private var previousTicks: (user: Double, system: Double, idle: Double, nice: Double)?
    private var timer: Timer?
    private var clients = 0

    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? 1 - diskFree / diskTotal : 0 }

    private init() {}

    func start() {
        clients += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func stop() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        uptime = ProcessInfo.processInfo.systemUptime
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = info.cpu_ticks
        let current = (user: Double(ticks.0), system: Double(ticks.1), idle: Double(ticks.2), nice: Double(ticks.3))
        if let previous = previousTicks {
            let user = current.user - previous.user
            let system = current.system - previous.system
            let idle = current.idle - previous.idle
            let nice = current.nice - previous.nice
            let total = user + system + idle + nice
            cpu = total > 0 ? (user + system + nice) / total : 0
            cpuHistory.append(cpu)
            if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
        }
        previousTicks = current
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = Double(getpagesize())
        let used = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        memoryUsed = used * pageSize
    }

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        diskTotal = Double(values.volumeTotalCapacity ?? 0)
    }
}
