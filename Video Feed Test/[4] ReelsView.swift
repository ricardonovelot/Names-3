//
//  ReelsView.swift
//  Video Feed Test
//
//  Created by Ricardo Lopez Novelo on 10/1/25.
//

import SwiftUI

struct reelsView: View {
    @EnvironmentObject private var settings: AppSettings
    
    var body: some View {
        ZStack(alignment: .top) {
            TikTokFeedView(mode: .start)

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
    }
}

#Preview {
    reelsView()
        .environmentObject(AppSettings())
}
