import Foundation
import QuartzCore

enum BootTimeline {
    private static let t0: CFTimeInterval = CACurrentMediaTime()

    static func mark(_ name: String) {
        let dt = CACurrentMediaTime() - t0
        Diagnostics.log(String(format: "Boot[%.3fs] %@", dt, name))
    }
}