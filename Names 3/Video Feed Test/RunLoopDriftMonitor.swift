import Foundation
import QuartzCore
import os

#if DEBUG
final class RunLoopDriftMonitor {
    static let shared = RunLoopDriftMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var enabled = false

    func start() {
        guard !enabled else { return }
        enabled = true
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        Diagnostics.videoPerf("[Drift] monitor started")
    }

    func stop() {
        enabled = false
        displayLink?.invalidate()
        displayLink = nil
        Diagnostics.videoPerf("[Drift] monitor stopped")
    }

    @objc private func step(_ link: CADisplayLink) {
        let ts = link.timestamp
        defer { lastTimestamp = ts }
        guard lastTimestamp > 0 else { return }
        let dt = ts - lastTimestamp
        // 60Hz nominal frame budget ~16.7ms; tolerate up to 50ms before logging
        if dt > 0.050 {
            Diagnostics.videoPerf(String(format: "[Drift] main-runloop drift=%.1f ms", dt*1000))
        }
    }
}
#endif