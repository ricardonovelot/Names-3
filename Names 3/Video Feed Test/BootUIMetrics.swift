import Foundation
import os

@MainActor
final class BootUIMetrics {
    static let shared = BootUIMetrics()

    private var firstCellID: OSSignpostID?

    private var firstCellMountedID: OSSignpostID?
    private var didEndFirstCellMounted = false

    func beginFirstFrameToFirstCell() {
        guard firstCellID == nil else { return }
        Diagnostics.log("BootUIMetrics: begin FirstFrame→FeedFirstCellReady")
        Diagnostics.signpostBegin("FirstFrameToFeedFirstCellReady", id: &firstCellID)
    }

    func endFirstFrameToFirstCell() {
        Diagnostics.signpostEnd("FirstFrameToFeedFirstCellReady", id: firstCellID)
        Diagnostics.log("BootUIMetrics: end FirstFrame→FeedFirstCellReady")
        firstCellID = nil
    }

    func beginFirstFrameToFirstCellMounted() {
        guard firstCellMountedID == nil else { return }
        Diagnostics.log("BootUIMetrics: begin FirstFrame→FirstCellMounted")
        Diagnostics.signpostBegin("FirstFrameToFirstCellMounted", id: &firstCellMountedID)
    }

    func endFirstFrameToFirstCellMountedOnce() {
        guard !didEndFirstCellMounted else { return }
        Diagnostics.signpostEnd("FirstFrameToFirstCellMounted", id: firstCellMountedID)
        Diagnostics.log("BootUIMetrics: end FirstFrame→FirstCellMounted")
        firstCellMountedID = nil
        didEndFirstCellMounted = true
    }
}