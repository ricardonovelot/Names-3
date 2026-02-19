import Foundation
import os

@MainActor
final class BootSignpostService: FeatureService {
    let key = "bootSignpost"

    private var didStart = false
    private var task: Task<Void, Never>?
    private var signpostID: OSSignpostID?

    func prepare() async {
        Diagnostics.log("BootSignpost prepare")
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        Diagnostics.log("BootSignpost start")
        let id = Diagnostics.signpostBegin("BootToFirstFrame", id: &signpostID)

        task = Task.detached { [signpostID] in
            let ok = await PhaseGate.shared.waitUntil(.firstFrame, timeout: 5)
            await MainActor.run {
                Diagnostics.signpostEnd("BootToFirstFrame", id: signpostID)
                Diagnostics.log("BootSignpost end ok=\(ok)")
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
    }
}