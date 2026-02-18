//
//  ProcessMemoryReporter.swift
//  Names 3
//
//  Reports current process memory (phys_footprint) for diagnostics.
//  Used by ProcessReportCoordinator so memory warning and background dumps include actual MB.
//  For debugging only; Apple discourages production use of task_info for memory.
//

import Foundation
import Darwin

enum ProcessMemoryReporter {
    /// Current process physical memory footprint in MB, or nil if task_info fails.
    /// Matches what Xcode Debug Navigator and Instruments show for the process.
    static func currentMegabytes() -> Float? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        return Float(info.phys_footprint) / (1024 * 1024)
    }

    /// Formatted string for logging, e.g. "142 MB" or "?"
    static var currentMegabytesString: String {
        guard let mb = currentMegabytes() else { return "?" }
        return String(format: "%.0f MB", mb)
    }
}
