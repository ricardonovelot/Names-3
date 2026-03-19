import SwiftUI
import StoreKit

struct VideoFeedSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var appleMusic: MusicLibraryModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Overlay") {
                    Toggle("Show download overlay", isOn: $settings.showDownloadOverlay)
                    Toggle("Show dimensions on photos", isOn: Binding(
                        get: { ExcludeScreenshotsPreference.showDimensionOverlay },
                        set: { ExcludeScreenshotsPreference.showDimensionOverlay = $0 }
                    ))
                    Toggle("Exclude device screenshots", isOn: Binding(
                        get: { ExcludeScreenshotsPreference.excludeScreenshots },
                        set: {
                            ExcludeScreenshotsPreference.excludeScreenshots = $0
                            NotificationCenter.default.post(name: .feedSettingsDidChange, object: nil)
                        }
                    ))
                }

                Section("Photo Grouping") {
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text("Between Videos")
                            .foregroundStyle(.secondary)
                    }
                    Text(FeedPhotoGroupingMode.betweenVideo.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
