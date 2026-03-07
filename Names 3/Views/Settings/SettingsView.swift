import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.connectivityMonitor) private var connectivityMonitor
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Photo Grouping")
                        Spacer()
                        Text("Between Videos")
                            .foregroundStyle(.secondary)
                    }
                    Text(FeedPhotoGroupingMode.betweenVideo.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { ExcludeScreenshotsPreference.excludeScreenshots },
                        set: {
                            ExcludeScreenshotsPreference.excludeScreenshots = $0
                            postFeedSettingsChanged()
                        }
                    )) {
                        Text("Exclude device screenshots")
                    }
                    Text("When on, hides images with device dimensions (1170×2532, etc.). Turn off to see film photos saved as screenshots.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { ExcludeScreenshotsPreference.showDimensionOverlay },
                        set: { ExcludeScreenshotsPreference.showDimensionOverlay = $0 }
                    )) {
                        Text("Show dimensions on photos")
                    }
                    Text("Overlay pixel size (e.g. 1170×2532) on feed images to identify screenshots that slip through.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Feed Photos")
                } footer: {
                    Text("Photos appear as carousels between videos in the feed.")
                }

                feedArchitectureSection

                if feedArchMode == FeedArchitectureMode.original.rawValue {
                    feedInitialVarietySection
                    feedExploreSection
                }

                photoArchitectureSection

                carouselSamplingSection

                if let connectivityMonitor {
                    Section {
                        HStack {
                            Image(systemName: connectivityMonitor.isOffline ? "wifi.slash" : "wifi")
                                .foregroundStyle(connectivityMonitor.isOffline ? .orange : .secondary)
                            Text(LocalizedStringKey("settings.connectivity.status"))
                            Spacer()
                            Text(connectivityMonitor.isOffline
                                 ? String(localized: "settings.connectivity.offline")
                                 : String(localized: "settings.connectivity.online"))
                                .foregroundStyle(.secondary)
                        }
                        Toggle(isOn: Binding(
                            get: { DataUsageGuardrails.allowsCellularForFeedMedia },
                            set: { DataUsageGuardrails.allowsCellularForFeedMedia = $0 }
                        )) {
                            Text(LocalizedStringKey("settings.cellular.useForFeed"))
                        }
                    } header: {
                        Text(LocalizedStringKey("settings.connectivity.header"))
                    } footer: {
                        Text(LocalizedStringKey("settings.cellular.useForFeedFooter"))
                    }
                }

                Section {
                    Button {
                        showOnboardingManually()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text(LocalizedStringKey("settings.onboarding.showAgain"))
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("settings.onboarding.header"))
                }

                Section {
                    NavigationLink {
                        QuickInputGuideView()
                    } label: {
                        HStack {
                            Image(systemName: "text.cursor")
                            Text("Quick Input Guide")
                        }
                    }

                    Picker("Quick Input Icon", selection: $quickInputExpandIcon) {
                        ForEach(QuickInputExpandIconPreference.allCases) { icon in
                            HStack {
                                Image(systemName: icon.systemImage)
                                Text(icon.rawValue)
                            }
                            .tag(icon.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Usage")
                } footer: {
                    Text("How to use the quick input bar to add names, tags, dates, and notes in one line. Icon A/B test: choose which icon appears when the bar is collapsed.")
                }

                practiceReminderSection

                storageSection

                Section {
                    HStack {
                        Text(LocalizedStringKey("settings.appInfo.version"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text(LocalizedStringKey("settings.appInfo.build"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(LocalizedStringKey("settings.appInfo.header"))
                }
            }
            .navigationTitle(LocalizedStringKey("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("settings.button.done")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Feed Architecture A/B Testing

    @AppStorage(FeedArchitectureMode.userDefaultsKey)
    private var feedArchMode: String = FeedArchitectureMode.original.rawValue

    private var feedArchitectureSection: some View {
        Section {
            Picker(LocalizedStringKey("settings.architecture.picker"), selection: $feedArchMode) {
                ForEach(FeedArchitectureMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)

            if let mode = FeedArchitectureMode(rawValue: feedArchMode) {
                Text(mode.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(LocalizedStringKey("settings.architecture.header"))
        } footer: {
            Text(LocalizedStringKey("settings.architecture.footer"))
        }
    }

    // MARK: - Feed Initial Variety (Original mode) — A/B test heuristics

    @AppStorage(FeedInitialVarietySettings.modeKey) private var feedInitialVarietyMode: String = FeedInitialVarietyMode.momentCluster.rawValue
    @AppStorage(FeedInitialVarietySettings.uniformMaxKey) private var feedInitialVarietyUniformMax: Int = 10
    @AppStorage(FeedInitialVarietySettings.momentGapKey) private var feedInitialVarietyMomentGap: Int = 30
    @AppStorage(FeedInitialVarietySettings.maxPerClusterKey) private var feedInitialVarietyMaxPerCluster: Int = 2
    @AppStorage(FeedInitialVarietySettings.maxPerDayKey) private var feedInitialVarietyMaxPerDay: Int = 12
    @AppStorage(FeedInitialVarietySettings.richDayClusterBonusKey) private var feedInitialVarietyRichDayBonus: Int = 8

    private var feedInitialVarietySection: some View {
        Section {
            Picker("Initial variety", selection: $feedInitialVarietyMode) {
                ForEach(FeedInitialVarietyMode.allCases) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: feedInitialVarietyMode) { _, _ in postFeedSettingsChanged() }
            Text(FeedInitialVarietyMode(rawValue: feedInitialVarietyMode)?.description ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if feedInitialVarietyMode == FeedInitialVarietyMode.uniform.rawValue {
                Stepper(value: $feedInitialVarietyUniformMax, in: 3...25) {
                    HStack {
                        Text("Max per day")
                        Spacer()
                        Text("\(feedInitialVarietyUniformMax)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: feedInitialVarietyUniformMax) { _, _ in postFeedSettingsChanged() }
            }

            if feedInitialVarietyMode == FeedInitialVarietyMode.momentCluster.rawValue || feedInitialVarietyMode == FeedInitialVarietyMode.richDay.rawValue {
                Stepper(value: $feedInitialVarietyMomentGap, in: 10...120) {
                    HStack {
                        Text("Moment gap (sec)")
                        Spacer()
                        Text("\(feedInitialVarietyMomentGap)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: feedInitialVarietyMomentGap) { _, _ in postFeedSettingsChanged() }
                Stepper(value: $feedInitialVarietyMaxPerCluster, in: 1...5) {
                    HStack {
                        Text("Max per moment")
                        Spacer()
                        Text("\(feedInitialVarietyMaxPerCluster)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: feedInitialVarietyMaxPerCluster) { _, _ in postFeedSettingsChanged() }
            }

            Stepper(value: $feedInitialVarietyMaxPerDay, in: 5...25) {
                HStack {
                    Text("Max per day (cap)")
                    Spacer()
                    Text("\(feedInitialVarietyMaxPerDay)")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: feedInitialVarietyMaxPerDay) { _, _ in postFeedSettingsChanged() }

            if feedInitialVarietyMode == FeedInitialVarietyMode.richDay.rawValue {
                Stepper(value: $feedInitialVarietyRichDayBonus, in: 0...15) {
                    HStack {
                        Text("Rich day bonus")
                        Spacer()
                        Text("\(feedInitialVarietyRichDayBonus)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: feedInitialVarietyRichDayBonus) { _, _ in postFeedSettingsChanged() }
            }
        } header: {
            Text("Initial variety")
        } footer: {
            Text("How many videos per day when opening the feed. Moment clusters: videos within 30s = same moment (avoids retakes). Rich day: more from days with many distinct moments.")
        }
        .onAppear {
            if feedInitialVarietyUniformMax < 3 { feedInitialVarietyUniformMax = 10 }
            if feedInitialVarietyMomentGap < 10 { feedInitialVarietyMomentGap = 30 }
            if feedInitialVarietyMaxPerCluster < 1 { feedInitialVarietyMaxPerCluster = 2 }
            if feedInitialVarietyMaxPerDay < 5 { feedInitialVarietyMaxPerDay = 12 }
            if feedInitialVarietyRichDayBonus < 0 { feedInitialVarietyRichDayBonus = 8 }
        }
    }

    // MARK: - Feed Explore (after recent days) — A/B test

    @AppStorage(FeedExploreSettings.recentDaysThresholdKey) private var feedExploreThreshold: Int = 9
    @AppStorage(FeedExploreSettings.exploreModeKey) private var feedExploreMode: String = FeedExploreMode.exponentialRandom.rawValue
    @AppStorage(FeedExploreSettings.exponentialDecayKey) private var feedExploreDecay: Double = 3

    private var feedExploreSection: some View {
        Section {
            Stepper(value: $feedExploreThreshold, in: 1...30) {
                HStack {
                    Text("Recent days before random")
                    Spacer()
                    Text("\(feedExploreThreshold)")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: feedExploreThreshold) { _, _ in postFeedSettingsChanged() }

            Picker("After threshold", selection: $feedExploreMode) {
                ForEach(FeedExploreMode.allCases) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: feedExploreMode) { _, _ in postFeedSettingsChanged() }
            Text(FeedExploreMode(rawValue: feedExploreMode)?.description ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if feedExploreMode == FeedExploreMode.exponentialRandom.rawValue {
                HStack {
                    Text("Decay factor")
                    Slider(value: $feedExploreDecay, in: 0.5...15, step: 0.5)
                        .onChange(of: feedExploreDecay) { _, _ in postFeedSettingsChanged() }
                    Text(String(format: "%.1f", feedExploreDecay))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        } header: {
            Text("Explore after recent")
        } footer: {
            Text("First N days: always prefer newest. After that: full random or exponential (recent preferred, decays toward random).")
        }
        .onAppear {
            if feedExploreThreshold < 1 { feedExploreThreshold = 9 }
            if feedExploreDecay < 0.5 { feedExploreDecay = 3 }
        }
    }

    // MARK: - Photo Architecture A/B Testing

    @AppStorage(PhotoArchitectureMode.userDefaultsKey)
    private var photoArchMode: String = PhotoArchitectureMode.original.rawValue

    private var photoArchitectureSection: some View {
        Section {
            Picker(LocalizedStringKey("settings.photo_architecture.picker"), selection: $photoArchMode) {
                ForEach(PhotoArchitectureMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)

            if let mode = PhotoArchitectureMode(rawValue: photoArchMode) {
                Text(mode.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(LocalizedStringKey("settings.photo_architecture.header"))
        } footer: {
            Text(LocalizedStringKey("settings.photo_architecture.footer"))
        }
    }

    // MARK: - Carousel sampling (uniform / density-adaptive)
    private var carouselSamplingSection: some View {
        Section {
            Picker("Sampling", selection: $carouselSamplingMode) {
                ForEach(CarouselSamplingMode.allCases) { m in
                    Text(m.rawValue).tag(m.rawValue)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: carouselSamplingMode) { _, _ in postFeedSettingsChanged() }
            Text(CarouselSamplingSettings.mode.description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if carouselSamplingMode == CarouselSamplingMode.uniform.rawValue {
                Stepper(value: $carouselUniformMax, in: 3...20) {
                    HStack {
                        Text("Max per carousel")
                        Spacer()
                        Text("\(carouselUniformMax)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: carouselUniformMax) { _, _ in postFeedSettingsChanged() }
            }

            if carouselSamplingMode == CarouselSamplingMode.densityAdaptive.rawValue {
                Stepper(value: $carouselDenseThreshold, in: 3...300) {
                    HStack {
                        Text("Dense threshold (sec)")
                        Spacer()
                        Text("\(carouselDenseThreshold)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: carouselDenseThreshold) { _, _ in postFeedSettingsChanged() }
                Stepper(value: $carouselSparseThreshold, in: 30...3600) {
                    HStack {
                        Text("Sparse threshold (sec)")
                        Spacer()
                        Text("\(carouselSparseThreshold)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: carouselSparseThreshold) { _, _ in postFeedSettingsChanged() }
                Stepper(value: $carouselMaxDense, in: 2...15) {
                    HStack {
                        Text("Max in burst")
                        Spacer()
                        Text("\(carouselMaxDense)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: carouselMaxDense) { _, _ in postFeedSettingsChanged() }
                Stepper(value: $carouselMaxSparse, in: 3...25) {
                    HStack {
                        Text("Max in session")
                        Spacer()
                        Text("\(carouselMaxSparse)")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: carouselMaxSparse) { _, _ in postFeedSettingsChanged() }
            }
        } header: {
            Text("Carousel Sampling")
        } footer: {
            Text("Reduce repetitive photos (e.g. many shots of same outfit). Uniform: first+last+evenly spaced. Density: fewer in bursts, more in deliberate sessions.")
        }
        .onAppear {
            if carouselUniformMax < 3 { carouselUniformMax = 8 }
            if carouselDenseThreshold < 3 { carouselDenseThreshold = 30 }
            if carouselSparseThreshold < 30 { carouselSparseThreshold = 120 }
            if carouselMaxDense < 2 { carouselMaxDense = 5 }
            if carouselMaxSparse < 3 { carouselMaxSparse = 12 }
        }
    }

    private func postFeedSettingsChanged() {
        NotificationCenter.default.post(name: .feedSettingsDidChange, object: nil)
    }

    @AppStorage(QuickInputExpandIconPreference.userDefaultsKey) private var quickInputExpandIcon: String = QuickInputExpandIconPreference.magnifyingglass.rawValue

    @AppStorage(CarouselSamplingSettings.modeKey) private var carouselSamplingMode: String = CarouselSamplingMode.none.rawValue
    @AppStorage(CarouselSamplingSettings.uniformMaxKey) private var carouselUniformMax: Int = 8
    @AppStorage(CarouselSamplingSettings.denseThresholdKey) private var carouselDenseThreshold: Int = 30
    @AppStorage(CarouselSamplingSettings.sparseThresholdKey) private var carouselSparseThreshold: Int = 120
    @AppStorage(CarouselSamplingSettings.maxDenseKey) private var carouselMaxDense: Int = 5
    @AppStorage(CarouselSamplingSettings.maxSparseKey) private var carouselMaxSparse: Int = 12

    // MARK: - Storage
    private var storageSection: some View {
        Section {
            NavigationLink {
                StorageManagerView()
            } label: {
                HStack {
                    Image(systemName: "externaldrive.badge.icloud")
                    Text("Storage")
                }
            }
        } header: {
            Text(LocalizedStringKey("storage.title"))
        } footer: {
            Text(LocalizedStringKey("storage.settings.footer"))
        }
    }

    // MARK: - Practice reminder (one daily notification for Face Quiz or Memory Rehearsal)
    private var practiceReminderSection: some View {
        let service = QuizReminderService.shared
        return Section {
            Toggle(isOn: Binding(
                get: { service.isDailyReminderEnabled },
                set: { newValue in
                    if newValue {
                        service.enableAndScheduleDailyReminder()
                    } else {
                        service.disableDailyReminder()
                    }
                }
            )) {
                HStack {
                    Image(systemName: "bell.badge")
                    Text(LocalizedStringKey("settings.practice.reminder"))
                }
            }
            Button {
                service.openAppNotificationSettings()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text(LocalizedStringKey("settings.practice.openNotificationSettings"))
                }
            }
        } header: {
            Text(LocalizedStringKey("settings.practice.header"))
        } footer: {
            Text(LocalizedStringKey("settings.practice.reminderFooter"))
        }
    }

    private func showOnboardingManually() {
        print("🔵 [Settings] Show onboarding tapped")
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            print("🔵 [Settings] Attempting to show onboarding after delay")
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                OnboardingCoordinatorManager.shared.showOnboarding(in: window, forced: true, modelContext: nil)
            }
        }
    }
    
}

#Preview {
    SettingsView()
        .modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
}