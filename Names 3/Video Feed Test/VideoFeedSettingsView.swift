import SwiftUI
import StoreKit

struct VideoFeedSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var appleMusic: MusicLibraryModel
    @State private var feedMode: FeedImplementationMode = FeedImplementationMode.current
    @State private var photoGroupingMode: FeedPhotoGroupingMode = FeedPhotoGroupingMode.current

    var body: some View {
        NavigationView {
            Form {
                Section("Overlay") {
                    Toggle("Show download overlay", isOn: $settings.showDownloadOverlay)
                }

                Section("Feed Implementation (A/B Test)") {
                    Picker("Mode", selection: $feedMode) {
                        ForEach(FeedImplementationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: feedMode) { _, new in
                        FeedImplementationMode.current = new
                    }
                    Text(feedMode.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Photo Grouping") {
                    Picker("Mode", selection: $photoGroupingMode) {
                        ForEach(FeedPhotoGroupingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: photoGroupingMode) { _, new in
                        FeedPhotoGroupingMode.current = new
                    }
                    Text(photoGroupingMode.description)
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
            .onAppear {
                feedMode = FeedImplementationMode.current
                photoGroupingMode = FeedPhotoGroupingMode.current
            }
            .task {
                appleMusic.bootstrap()
            }
        }
    }
}
