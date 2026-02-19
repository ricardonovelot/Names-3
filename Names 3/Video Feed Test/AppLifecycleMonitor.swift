import UIKit
import Combine

@MainActor
final class AppLifecycleMonitor {
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Start monitoring when the app becomes active.
        // This also covers the initial launch.
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in
                Diagnostics.log("Lifecycle: didBecomeActive")
                Task { await PhaseGate.shared.mark(.appActive) }
                Task { @MainActor in
                    await ServiceOrchestrator.shared.ensureStarted("performanceMonitor")
                }
            }
            .store(in: &cancellables)

        // Stop monitoring when the app enters the background to save resources.
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                Diagnostics.log("Lifecycle: didEnterBackground")
            }
            .store(in: &cancellables)
    }
}