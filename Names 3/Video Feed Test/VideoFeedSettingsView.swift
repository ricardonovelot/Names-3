import SwiftUI
import StoreKit

struct VideoFeedSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var appleMusic: MusicLibraryModel
    
    var body: some View {
        NavigationView {
            Form {
                Section("Overlay") {
                    Toggle("Show download overlay", isOn: $settings.showDownloadOverlay)
                }

                Section("Media") {
                    NavigationLink {
                        CurrentMonthGridView()
                    } label: {
                        Label("This Month (Grid)", systemImage: "calendar")
                    }
                }

                Section("YouTube Likes") {
                    if appleMusic.isGoogleConnected {
                        if appleMusic.isGoogleSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Syncing…")
                            }
                        } else {
                            HStack {
                                Button {
                                    appleMusic.retryGoogleSync()
                                } label: {
                                    Label("Sync Now", systemImage: "arrow.clockwise.circle")
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    appleMusic.disconnectGoogle()
                                } label: {
                                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                            if let last = appleMusic.lastGoogleSyncAt {
                                Text("Connected to Google. Last synced \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date())).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Connected to Google.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let msg = appleMusic.googleStatusMessage, !msg.isEmpty {
                            Text(msg).font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        if appleMusic.isGoogleSyncing {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Connecting…")
                            }
                        } else {
                            Button {
                                appleMusic.connectGoogle()
                            } label: {
                                Label("Connect Google Account", systemImage: "g.circle")
                            }
                        }
                        if let msg = appleMusic.googleStatusMessage, !msg.isEmpty {
                            Text(msg).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Trash") {
                    NavigationLink {
                        DeletedVideosView()
                    } label: {
                        HStack {
                            Label("Deleted videos", systemImage: "trash")
                            Spacer()
                            DeletedCountBadge()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                appleMusic.bootstrap()
            }
        }
    }
}
