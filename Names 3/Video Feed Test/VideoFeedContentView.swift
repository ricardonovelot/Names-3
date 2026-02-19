//
//  VideoFeedContentView.swift
//  Video Feed Test
//
//  Root view for the standalone Video Feed Test app. Names 3 uses TikTokFeedView directly in its tab.
//

import SwiftUI

struct VideoFeedContentView: View {
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
            BootTimeline.mark("VideoFeedContentView onAppear")
            Diagnostics.log("VideoFeedContentView onAppear")
            FirstLaunchProbe.shared.contentAppear()
            FirstLaunchProbe.shared.startMainDriftMonitor()
        }
        .onChange(of: scenePhase) { _, phase in
            Diagnostics.log("App scenePhase=\(String(describing: phase))")
        }
    }
}

#Preview {
    VideoFeedContentView()
        .environmentObject(AppSettings())
}
