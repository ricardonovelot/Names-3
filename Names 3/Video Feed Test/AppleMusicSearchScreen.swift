import SwiftUI
import Combine
import MediaPlayer
import MusicKit
import Photos
import UIKit

enum MusicLibraryTab: String, CaseIterable {
    case forYou = "For You"
    case recentlyAdded = "Recently Added"
    case saved = "Saved"
    case recentlyUsed = "Recently Used"
}

@MainActor
struct AppleMusicSearchScreen: View {
    /// Asset IDs to apply the song to (single video, carousel assets, or saved item). When multiple, applies to all. Ignored when albumIdentifier is set.
    let assetIDs: [String]
    /// When set (e.g. "album:localId"), song is attached at album level. All media in that album plays this song.
    let albumIdentifier: String?
    var onClose: () -> Void

    init(assetIDs: [String], albumIdentifier: String? = nil, onClose: @escaping () -> Void) {
        self.assetIDs = assetIDs
        self.albumIdentifier = albumIdentifier
        self.onClose = onClose
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AppleMusicSearchModel()
    @StateObject private var local = AppleMusicManager()

    @State private var assigned: SongReference?
    @State private var isRemoving = false
    @State private var isClosing = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var selectedTab: MusicLibraryTab = .forYou
    @State private var recentlyUsedSongs: [SongReference] = []

    var body: some View {
        NavigationStack {
            Group {
                if model.isSearching && model.results.isEmpty {
                    searchLoadingView
                } else if let err = model.error, model.results.isEmpty {
                    searchErrorView(message: err)
                } else if model.hasSearched && model.results.isEmpty {
                    searchNoResultsView
                } else if !model.results.isEmpty {
                    searchResultsList
                } else {
                    VStack(spacing: 0) {
                        Picker("Section", selection: $selectedTab) {
                            ForEach(MusicLibraryTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        tabContentView
                    }
                }
            }
            .navigationTitle("Search Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, prompt: "Song, artist, or album")
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onSubmit { model.submitSearch(limit: 25) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close", systemImage: "xmark") { close() }
                        .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let assigned {
                    assignedSection(assigned)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(.bar)
                }
            }
        }
        .onAppear {
            Task {
                if let albumId = albumIdentifier, albumId.hasPrefix("album:") {
                    assigned = await VideoAudioOverrides.shared.songReference(for: assetIDs.first, albumIdentifier: albumId)
                } else if let firstID = assetIDs.first {
                    assigned = await VideoAudioOverrides.shared.songReference(for: firstID)
                } else {
                    assigned = nil
                }
                if MusicAuthorization.currentStatus == .notDetermined {
                    _ = await MusicAuthorization.request()
                }
                if local.authorization == .authorized {
                    local.loadRecent(limit: 50)
                    if let assetDate = await fetchAssetCreationDate() {
                        local.loadForYou(assetDate: assetDate, limit: 25)
                    }
                }
                recentlyUsedSongs = await VideoAudioOverrides.shared.recentlyUsedSongs(limit: 25)
            }
        }
        .onChange(of: model.query) { _, newValue in
            debounceTask?.cancel()
            let term = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.count >= 3 else {
                if term.isEmpty { model.clear() }
                return
            }
            debounceTask = Task { [weak model] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    model?.submitSearch(limit: 25)
                }
            }
        }
    }

    private var searchLoadingView: some View {
        ContentUnavailableView {
            Label("Searching", systemImage: "magnifyingglass")
        } description: {
            Text("Finding songs in Apple Music…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchNoResultsView: some View {
        ContentUnavailableView.search(text: model.query)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func searchErrorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Search", systemImage: "exclamationmark.circle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { model.submitSearch(limit: 25) }
                .buttonStyle(.borderedProminent)
            if message.contains("Allow Apple Music") || message.contains("denied") {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchResultsList: some View {
        List {
            Section {
                ForEach(model.results, id: \.storeID) { song in
                    SearchResultRow(song: song) {
                        Task {
                            let ref = SongReference.appleMusic(
                                storeID: song.storeID,
                                title: song.title,
                                artist: song.artist
                            )
                            if let albumId = albumIdentifier, albumId.hasPrefix("album:") {
                                await VideoAudioOverrides.shared.setSongReference(forAlbumIdentifier: albumId, reference: ref)
                            } else {
                                for id in assetIDs {
                                    await VideoAudioOverrides.shared.setSongReference(for: id, reference: ref)
                                }
                            }
                            assigned = await VideoAudioOverrides.shared.songReference(for: assetIDs.first, albumIdentifier: albumIdentifier)
                            await MusicBootstrapper.shared.ensureBootstrapped()
                            AppleMusicController.shared.play(storeID: song.storeID)
                            close()
                        }
                    }
                }
            } header: {
                Text("Songs")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var tabContentView: some View {
        Group {
            switch local.authorization {
            case .authorized:
                tabContentWhenAuthorized
            case .notDetermined:
                authorizationPromptView
            case .denied, .restricted:
                settingsPromptView
            @unknown default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var tabContentWhenAuthorized: some View {
        switch selectedTab {
        case .forYou:
            forYouSection
        case .recentlyAdded:
            recentlyAddedSection
        case .saved:
            savedSection
        case .recentlyUsed:
            recentlyUsedSection
        }
    }

    private var forYouSection: some View {
        List {
            if local.forYouItems.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("For You", systemImage: "sparkles")
                    } description: {
                        Text("Songs from your library added around the time this media was created.")
                    }
                }
            } else {
                Section("For You") {
                    ForEach(local.forYouItems, id: \.persistentID) { item in
                        LibraryRow(item: item) { applyAndPlay(item: item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var recentlyAddedSection: some View {
        List {
            if local.recentItems.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Recently Added", systemImage: "music.note.list")
                    } description: {
                        Text("Songs you've recently added to your library will appear here.")
                    }
                }
            } else {
                Section("Recently Added") {
                    ForEach(local.recentItems, id: \.persistentID) { item in
                        LibraryRow(item: item) { applyAndPlay(item: item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var savedSection: some View {
        List {
            Section {
                ContentUnavailableView {
                    Label("Saved", systemImage: "bookmark")
                } description: {
                    Text("Save your favorite songs for quick access.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var recentlyUsedSection: some View {
        List {
            if recentlyUsedSongs.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Recently Used", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Songs you've assigned to videos will appear here.")
                    }
                }
            } else {
                Section("Recently Used") {
                    ForEach(recentlyUsedSongs, id: \.debugKey) { ref in
                        SongReferenceRow(reference: ref) {
                            Task {
                                await applyAndPlay(reference: ref)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var authorizationPromptView: some View {
        List {
            Section {
                Button {
                    local.requestAuthorization()
                } label: {
                    Label("Allow Apple Music Access", systemImage: "music.note.list")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var settingsPromptView: some View {
        List {
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
        }
        .listStyle(.insetGrouped)
    }

    private func applyAndPlay(item: MPMediaItem) {
        Task {
            let storeID: String? = item.value(forProperty: MPMediaItemPropertyPlaybackStoreID) as? String
            if let storeID, !storeID.isEmpty {
                let ref = SongReference.appleMusic(
                    storeID: storeID,
                    title: item.title,
                    artist: item.artist
                )
                if let albumId = albumIdentifier, albumId.hasPrefix("album:") {
                    await VideoAudioOverrides.shared.setSongReference(forAlbumIdentifier: albumId, reference: ref)
                } else {
                    for id in assetIDs {
                        await VideoAudioOverrides.shared.setSongReference(for: id, reference: ref)
                    }
                }
                assigned = await VideoAudioOverrides.shared.songReference(for: assetIDs.first, albumIdentifier: albumIdentifier)
            }
            await MusicBootstrapper.shared.ensureBootstrapped()
            local.play(item: item)
            close()
        }
    }

    private func applyAndPlay(reference: SongReference) async {
        guard let storeID = reference.appleMusicStoreID, !storeID.isEmpty else { return }
        if let albumId = albumIdentifier, albumId.hasPrefix("album:") {
            await VideoAudioOverrides.shared.setSongReference(forAlbumIdentifier: albumId, reference: reference)
        } else {
            for id in assetIDs {
                await VideoAudioOverrides.shared.setSongReference(for: id, reference: reference)
            }
        }
        assigned = await VideoAudioOverrides.shared.songReference(for: assetIDs.first, albumIdentifier: albumIdentifier)
        await MusicBootstrapper.shared.ensureBootstrapped()
        AppleMusicController.shared.play(storeID: storeID)
        close()
    }

    private func fetchAssetCreationDate() async -> Date? {
        guard let firstID = assetIDs.first else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [firstID], options: nil)
        return assets.firstObject?.creationDate
    }

    private func assignedSection(_ ref: SongReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(albumIdentifier != nil ? "Assigned to this album" : (assetIDs.count > 1 ? "Assigned to this item" : "Assigned to this video"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title ?? "Unknown Title")
                        .font(.subheadline.bold())
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
                            guard !assetIDs.isEmpty || albumIdentifier != nil else { return }
                            isRemoving = true
                            if let albumId = albumIdentifier, albumId.hasPrefix("album:") {
                                await VideoAudioOverrides.shared.setSongReference(forAlbumIdentifier: albumId, reference: nil)
                            } else {
                                for id in assetIDs {
                                    await VideoAudioOverrides.shared.setSongReference(for: id, reference: nil)
                                }
                            }
                            AppleMusicController.shared.pauseIfManaged()
                            AppleMusicController.shared.stopManaging()
                            assigned = await VideoAudioOverrides.shared.songReference(for: assetIDs.first, albumIdentifier: albumIdentifier)
                            isRemoving = false
                        }
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Remove song from this video")
                } else {
                    ProgressView()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
        }
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
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SongReferenceRow: View {
    let reference: SongReference
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.title ?? "Unknown Title")
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(reference.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
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
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(item.artist ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
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
                Color(.secondarySystemFill)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            @unknown default:
                Color(.secondarySystemFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
