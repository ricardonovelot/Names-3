import Foundation
import AVFoundation

extension AVAsset {
    func asyncLoadValues(forKeys keys: [String]) async -> [String: AVKeyValueStatus] {
        await withCheckedContinuation { cont in
            loadValuesAsynchronously(forKeys: keys) {
                var result: [String: AVKeyValueStatus] = [:]
                for k in keys {
                    var err: NSError?
                    let st = self.statusOfValue(forKey: k, error: &err)
                    result[k] = st
                }
                cont.resume(returning: result)
            }
        }
    }
}

extension AVAssetTrack {
    func asyncLoadValues(forKeys keys: [String]) async -> [String: AVKeyValueStatus] {
        await withCheckedContinuation { cont in
            loadValuesAsynchronously(forKeys: keys) {
                var result: [String: AVKeyValueStatus] = [:]
                for k in keys {
                    var err: NSError?
                    let st = self.statusOfValue(forKey: k, error: &err)
                    result[k] = st
                }
                cont.resume(returning: result)
            }
        }
    }
}