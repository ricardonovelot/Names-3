import Foundation

actor MusicBootstrapper {
    static let shared = MusicBootstrapper()
    private var started = false
    private var inFlight: Task<Void, Never>?

    func ensureBootstrapped() async {
        if started { return }
        if let t = inFlight {
            await t.value
            return
        }
        Diagnostics.log("MusicBootstrapper: ensureBootstrapped begin")
        let task = Task { @MainActor in
            await ServiceOrchestrator.shared.ensureStarted("appleMusic")
        }
        inFlight = task
        await task.value
        inFlight = nil
        started = true
        Diagnostics.log("MusicBootstrapper: ensureBootstrapped end")
    }
}