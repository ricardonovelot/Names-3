import Foundation
import Combine
import Network
import os
import UIKit

@MainActor
final class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    struct Snapshot: Sendable {
        let timestamp: Date
        let fps: Double
        let memoryFootprintMB: Double?
        let thermalState: ProcessInfo.ThermalState
        let isLowPowerModeEnabled: Bool
        let batteryLevel: Double?
        let batteryState: UIDevice.BatteryState
        let networkStatus: NWPath.Status
        let isCellular: Bool
        let isConstrained: Bool
        let isExpensive: Bool
        let cpuSystemBusyPercent: Double?
    }

    @Published private(set) var latest: Snapshot?

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "perf.path.monitor")
    private var path: NWPath?
    private var samplingTask: Task<Void, Never>?
    private var logCounter = 0

    private init() {}

    func start() {
        guard samplingTask == nil else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true
        FPSMonitor.shared.start()

        pathMonitor.pathUpdateHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                self?.path = p
            }
        }
        pathMonitor.start(queue: pathQueue)

        samplingTask = Task.detached { [weak self] in
            await self?.runSampler()
        }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        pathMonitor.cancel()
        FPSMonitor.shared.stop()
    }

    private func post(_ snap: Snapshot) {
        latest = snap
    }

    private func networkSnapshot() -> (NWPath.Status, Bool, Bool, Bool) {
        let p = path
        let status = p?.status ?? .requiresConnection
        let isCellular = p?.usesInterfaceType(.cellular) ?? false
        let isConstrained = p?.isConstrained ?? false
        let isExpensive = p?.isExpensive ?? false
        return (status, isCellular, isConstrained, isExpensive)
    }

    private func batterySnapshot() -> (Double?, UIDevice.BatteryState) {
        let lvl = UIDevice.current.batteryLevel
        let level = lvl >= 0 ? Double(lvl) : nil
        return (level, UIDevice.current.batteryState)
    }

    private func buildSnapshot(fps: Double, memMB: Double?, cpuBusyPct: Double?) -> Snapshot {
        let (status, isCellular, isConstrained, isExpensive) = networkSnapshot()
        let (batteryLevel, batteryState) = batterySnapshot()
        return Snapshot(
            timestamp: Date(),
            fps: fps,
            memoryFootprintMB: memMB,
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            networkStatus: status,
            isCellular: isCellular,
            isConstrained: isConstrained,
            isExpensive: isExpensive,
            cpuSystemBusyPercent: cpuBusyPct
        )
    }

    private func logIfNeeded(_ s: Snapshot) {
        logCounter &+= 1
        if logCounter % 5 == 0 {
            let mem = s.memoryFootprintMB.map { String(format: "%.1f", $0) } ?? "n/a"
            let cpu = s.cpuSystemBusyPercent.map { String(format: "%.0f%%", $0) } ?? "n/a"
            Diagnostics.log("Perf: fps=\(String(format: "%.1f", s.fps)) mem=\(mem)MB cpu=\(cpu) therm=\(s.thermalState.rawValue) lowPwr=\(s.isLowPowerModeEnabled) net=\(String(describing: s.networkStatus)) cell=\(s.isCellular) exp=\(s.isExpensive) constr=\(s.isConstrained)")
        }
        if s.thermalState == .serious || s.thermalState == .critical {
            Diagnostics.log("Perf WARNING: thermal=\(s.thermalState.rawValue)")
        }
    }

    private func runSampler() async {
        var prevCPU: host_cpu_load_info_data_t?
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))

            if Task.isCancelled { break }

            let memBytes = Self.memoryFootprintBytes()
            let memMB = memBytes.map { Double($0) / (1024.0 * 1024.0) }

            let cpuBusy = Self.systemCPUBusyPercent(previous: &prevCPU)

            let fps = await MainActor.run { FPSMonitor.shared.fps }

            let snap = await MainActor.run { buildSnapshot(fps: fps, memMB: memMB, cpuBusyPct: cpuBusy) }
            await MainActor.run {
                post(snap)
                logIfNeeded(snap)
            }
        }
    }

    private static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return UInt64(info.phys_footprint)
        } else {
            return nil
        }
    }

    private static func systemCPUBusyPercent(previous prev: inout host_cpu_load_info_data_t?) -> Double? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        defer { prev = info }

        guard let p = prev else { return nil }

        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys  = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)

        let total = user + sys + idle + nice
        guard total > 0 else { return nil }

        let busy = (user + sys + nice) / total
        return busy * 100.0
    }
}