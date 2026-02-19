import Foundation
import UIKit

@MainActor
final class PerformanceMonitorService: FeatureService {
    let key = "performanceMonitor"

    private var didStart = false
    private var didInstallObservers = false

    func prepare() async {
        if !didInstallObservers {
            didInstallObservers = true
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                Diagnostics.log("PerfService: didBecomeActive -> start")
                PerformanceMonitor.shared.start()
            }
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                Diagnostics.log("PerfService: didEnterBackground -> stop")
                PerformanceMonitor.shared.stop()
            }
        }
        Diagnostics.log("PerformanceMonitorService prepare")
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        _ = await PhaseGate.shared.waitUntil(.appActive, timeout: 5)
        Diagnostics.log("PerformanceMonitorService start -> PerformanceMonitor.start()")
        FirstLaunchProbe.shared.mark("PerfMon.start.begin onMain=\(Thread.isMainThread)")
        PerformanceMonitor.shared.start()
        FirstLaunchProbe.shared.mark("PerfMon.start.end")
    }

    func stop() async {
        Diagnostics.log("PerformanceMonitorService stop -> PerformanceMonitor.stop()")
        PerformanceMonitor.shared.stop()
    }
}