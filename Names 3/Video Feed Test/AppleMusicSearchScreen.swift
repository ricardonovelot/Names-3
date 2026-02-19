import SwiftUI
import Combine
import MediaPlayer
import UIKit

@MainActor
struct AppleMusicSearchScreen: View {
    let assetID: String?
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppleMusicSearchModel()
    @StateObject private var local = AppleMusicManager()

    @State private var assigned: SongReference?
    @State private var isRemoving = false
    @State private var isClosing = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if let assigned {
                    assignedSection(assigned)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                Divider().opacity(0.4)

                content
            }
            .navigationTitle("Search Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onAppear {
            Task {
                if let id = assetID {
                    assigned = await VideoAudioOverrides.shared.songReference(for: id)
                } else {
                    assigned = nil
                }
            }
            if local.authorization == .authorized {
                local.loadRecent(limit: 50)
            }
        }
        .onChange(of: model.query) { _, newValue in
            debounceTask?.cancel()
            let term = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 3 else { return }
            debounceTask = Task { [weak model] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    model?.submitSearch(limit: 25)
                }
            }
        }
    }

    private var content: some View {
        Group {
            if !AppleMusicCatalog.isConfigured {
                stateMessage(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .yellow,
                    title: "Missing Apple Music developer token.",
                    subtitle: "Set APPLE_MUSIC_DEVELOPER_TOKEN in Info.plist."
                )
            } else if model.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
            } else if let err = model.error {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(err).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry") { model.submitSearch(limit: 25) }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 8)
            } else if !model.results.isEmpty {
                List {
                    Section {
                        ForEach(model.results, id: \.storeID) { song in
                            SearchResultRow(song: song) {
                                Task {
                                    if let id = assetID {
                                        await VideoAudioOverrides.shared.setSongReference(
                                            for: id,
                                            reference: SongReference.appleMusic(
                                                storeID: song.storeID,
                                                title: song.title,
                                                artist: song.artist
                                            )
                                        )
                                        assigned = await VideoAudioOverrides.shared.songReference(for: id)
                                    }
                                    await MusicBootstrapper.shared.ensureBootstrapped()
                                    AppleMusicController.shared.play(storeID: song.storeID)
                                    close()
                                }
                            }
                        }
                    } header: {
                        Text("Results (\(model.results.count))")
                            .font(.caption.weight(.semibold))
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                // Default view: user's library (known songs)
                List {
                    switch local.authorization {
                    case .authorized:
                        if local.recentItems.isEmpty {
                            Section {
                                stateRow(
                                    icon: "music.note",
                                    title: "No recent songs found in your library.",
                                    subtitle: "Try Apple Music search above."
                                )
                            }
                        } else {
                            Section("Your Library") {
                                ForEach(local.recentItems, id: \.persistentID) { item in
                                    LibraryRow(item: item) {
                                        Task {
                                            if let id = assetID {
                                                // Robust optional fetch for store ID across SDKs
                                                let storeID: String? = item.value(forProperty: MPMediaItemPropertyPlaybackStoreID) as? String
                                                if let storeID, !storeID.isEmpty {
                                                    await VideoAudioOverrides.shared.setSongReference(
                                                        for: id,
                                                        reference: SongReference.appleMusic(
                                                            storeID: storeID,
                                                            title: item.title,
                                                            artist: item.artist
                                                        )
                                                    )
                                                    assigned = await VideoAudioOverrides.shared.songReference(for: id)
                                                }
                                            }
                                            await MusicBootstrapper.shared.ensureBootstrapped()
                                            local.play(item: item)
                                            close()
                                        }
                                    }
                                }
                            }
                        }
                    case .notDetermined:
                        Section {
                            Button {
                                local.requestAuthorization()
                            } label: {
                                Label("Allow Apple Music Access", systemImage: "music.note.list")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    case .denied, .restricted:
                        Section {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings to Allow Apple Music", systemImage: "gearshape")
                            }
                            .buttonStyle(.bordered)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Song, artist, or keyword", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .onSubmit { model.submitSearch(limit: 25) }
                if !model.query.isEmpty {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button {
                model.submitSearch(limit: 25)
            } label: {
                Text("Search")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(model.canSearch ? 0.14 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!model.canSearch)
        }
    }

    private func assignedSection(_ ref: SongReference) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assigned to this video")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title ?? "Unknown Title")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(ref.artist ?? "Unknown Artist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !isRemoving {
                    Button {
                        Task {
                            guard let id = assetID else { return }
                            isRemoving = true
                            await VideoAudioOverrides.shared.setSongReference(for: id, reference: nil)
                            AppleMusicController.shared.pauseIfManaged()
                            AppleMusicController.shared.stopManaging()
                            assigned = await VideoAudioOverrides.shared.songReference(for: id)
                            isRemoving = false
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color(.tertiarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove song from this video")
                } else {
                    ProgressView()
                        .frame(width: 40, height: 20)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private func stateMessage(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(iconColor)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
    }

    private func stateRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote).foregroundStyle(.secondary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func close() {
        guard !isClosing else { return }
        isClosing = true
        onClose()
        dismiss()
    }
}

private struct SearchResultRow: View {
    let song: AppleCatalogSong
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Artwork(url: song.artworkURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryRow: View {
    let item: MPMediaItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                let size: CGFloat = 48

                // Robust thumbnail to avoid type-checker confusion; apply frame/clip outside conditional
                Group {
                    if let art = item.artwork?.image(at: CGSize(width: size * 2, height: size * 2)) {
                        Image(uiImage: art)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color(.secondarySystemFill)
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Unknown Title")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(item.artist ?? "Unknown Artist")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct Artwork: View {
    let url: URL?
    var body: some View {
        let size: CGFloat = 48
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                Color(.secondarySystemFill)
            case .failure:
                Color(.secondarySystemFill).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            @unknown default:
                Color(.secondarySystemFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}