import Foundation
import Combine

@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    static let shared = NetworkSpeedMonitor()
    @Published var downloadBps: Double = 0
    private init() {}
}