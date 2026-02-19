//
//  Video_Feed_TestApp.swift
//  Video Feed Test
//
//  Created by Ricardo Lopez Novelo on 10/1/25.
//

import SwiftUI

@main
struct Video_Feed_TestApp: App {
    @StateObject private var settings = AppSettings()
    
    // This monitor handles starting/stopping services based on app lifecycle events.
    private let lifecycleMonitor = AppLifecycleMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BootTimeline.mark("App init")
        Task { await PhaseGate.shared.mark(.appInit) }
        Task { @MainActor in
            ServiceOrchestrator.shared.register(BootSignpostService())
            ServiceOrchestrator.shared.register(PerformanceMonitorService())
            ServiceOrchestrator.shared.register(MusicLibraryPrefetchService())
            ServiceOrchestrator.shared.register(AppleMusicFeatureService())

            await ServiceOrchestrator.shared.ensureStarted("bootSignpost")
        }
        FirstLaunchProbe.shared.appInit()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .onAppear {
                    BootTimeline.mark("Root ContentView appeared")
                    Diagnostics.log("App root content appeared")
                    Task { @MainActor in
                        // Safe to kick; services themselves will wait for gates.
                        await ServiceOrchestrator.shared.ensureStarted("musicLibraryPrefetch")
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    Diagnostics.log("App scenePhase=\(String(describing: phase))")
                }
        }
    }
}