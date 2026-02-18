import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.connectivityMonitor) private var connectivityMonitor

    var body: some View {
        NavigationStack {
            List {
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
                    } header: {
                        Text(LocalizedStringKey("settings.connectivity.header"))
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
                } header: {
                    Text("Usage")
                } footer: {
                    Text("How to use the quick input bar to add names, tags, dates, and notes in one line.")
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