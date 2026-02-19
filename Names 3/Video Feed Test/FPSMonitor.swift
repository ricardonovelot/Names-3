import Foundation
import QuartzCore
import Combine
import UIKit

@MainActor
final class FPSMonitor: ObservableObject {
    static let shared = FPSMonitor()

    @Published private(set) var fps: Double = 0

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var windowStart: CFTimeInterval = 0

    private init() {}

    func start() {
        guard link == nil else { return }
        lastTimestamp = 0
        frameCount = 0
        windowStart = CACurrentMediaTime()
        let proxy = DisplayLinkProxy { [weak self] ts in
            self?.step(ts: ts)
        }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        proxy.ownerLink = l
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    private func step(ts: CFTimeInterval) {
        if lastTimestamp == 0 {
            lastTimestamp = ts
            windowStart = ts
            return
        }
        frameCount &+= 1
        let dt = ts - windowStart
        if dt >= 1.0 {
            let value = Double(frameCount) / dt
            fps = min(120, max(0, value))
            frameCount = 0
            windowStart = ts
        }
        lastTimestamp = ts
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    var callback: (CFTimeInterval) -> Void
    weak var ownerLink: CADisplayLink?

    init(callback: @escaping (CFTimeInterval) -> Void) {
        self.callback = callback
    }

    @objc func tick(_ sender: CADisplayLink) {
        callback(sender.timestamp)
    }

    deinit {
        ownerLink?.invalidate()
    }
}