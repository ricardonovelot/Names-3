//
//  VideoStateLog.swift
//  Names 3
//
//  Lightweight state logging for video load→display pipeline.
//  Grep for [VideoState] to trace any asset. Used to debug black-screen issues.
//  Minimal overhead: single print, no allocation in hot paths.
//
//  Pipeline states: S01_requested → S02/S03/S04 → S05→S06 → S07/S08/S09 (load/play)
//  Display pipeline: S10_cell_active → S11_layer_bound → S12_layer_ready → S13_overlay_hidden → S14_fully_visible
//

import Foundation

enum VideoStateLog {

    private static func tag(_ id: String) -> String {
        String(id.prefix(16))
    }

    /// Log a video state transition. Use consistent state names for grepping.
    static func log(id: String, state: String, extra: String = "") {
        let t = tag(id)
        if extra.isEmpty {
            print("[VideoState] \(t) \(state)")
        } else {
            print("[VideoState] \(t) \(state) \(extra)")
        }
    }
}
