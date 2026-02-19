//
//  ContentView.swift
//  Video Feed Test
//
//  Created by Ricardo Lopez Novelo on 10/1/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack(alignment: .top) {
            TikTokFeedView()

            if settings.showDownloadOverlay {
                DownloadOverlayView()
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                    .onTapGesture(count: 2) {
                        settings.showDownloadOverlay = false
                    }
            }
        }
        .statusBar(hidden: true)
        .reportFirstFrame()
        .onAppear {
            BootTimeline.mark("ContentView onAppear")
            Diagnostics.log("ContentView onAppear")
            FirstLaunchProbe.shared.contentAppear()
            FirstLaunchProbe.shared.startMainDriftMonitor()
        }
        .onChange(of: scenePhase) { _, phase in
            Diagnostics.log("App scenePhase=\(String(describing: phase))")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}