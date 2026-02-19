import Foundation
import os
import QuartzCore

@MainActor
protocol FeatureService {
    var key: String { get }
    func prepare() async
    func start() async
    func stop() async
}

@MainActor
final class ServiceOrchestrator {
    static let shared = ServiceOrchestrator()
    private var services: [String: any FeatureService] = [:]
    private var started: Set<String> = []
    private var preparing: Set<String> = []

    private enum StartGate {
        case none
        case afterFirstVideo(delay: TimeInterval)
    }
    private let criticalGates: [String: StartGate] = [
        "musicLibraryPrefetch": .afterFirstVideo(delay: 0),
        "performanceMonitor": .afterFirstVideo(delay: 5)
    ]

    func register(_ service: any FeatureService) {
        services[service.key] = service
    }

    func ensureStarted(_ key: String) async {
        guard let svc = services[key] else {
            Diagnostics.log("Orchestrator: service \(key) not registered")
            return
        }
        if started.contains(key) { return }

        if !preparing.contains(key) {
            preparing.insert(key)
            var spPrepare: OSSignpostID?
            Diagnostics.signpostBegin("ServicePrepare", id: &spPrepare)
            let t0 = CACurrentMediaTime()
            FirstLaunchProbe.shared.servicePrepareBegin(key: key, onMain: Thread.isMainThread)
            await svc.prepare()
            FirstLaunchProbe.shared.servicePrepareEnd(key: key, onMain: Thread.isMainThread)
            let dt = CACurrentMediaTime() - t0
            Diagnostics.log(#"Orchestrator: \#(key) prepare dt=\#(String(format: "%.3f", dt))s onMain=\#(Thread.isMainThread)"#)
            Diagnostics.signpostEnd("ServicePrepare", id: spPrepare)
            preparing.remove(key)
        }

        if let gate = criticalGates[key] {
            switch gate {
            case .none:
                break
            case .afterFirstVideo(let delay):
                _ = await PhaseGate.shared.waitUntil(.firstVideoReady, timeout: 600)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }

        var spStart: OSSignpostID?
        Diagnostics.signpostBegin("ServiceStart", id: &spStart)
        let t1 = CACurrentMediaTime()
        FirstLaunchProbe.shared.serviceStartBegin(key: key, onMain: Thread.isMainThread)
        await svc.start()
        FirstLaunchProbe.shared.serviceStartEnd(key: key, onMain: Thread.isMainThread)
        let dtStart = CACurrentMediaTime() - t1
        Diagnostics.log(#"Orchestrator: \#(key) start dt=\#(String(format: "%.3f", dtStart))s onMain=\#(Thread.isMainThread)"#)
        Diagnostics.signpostEnd("ServiceStart", id: spStart)

        started.insert(key)
        Diagnostics.log("Orchestrator: started \(key)")
    }
}