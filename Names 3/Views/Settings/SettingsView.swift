import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showOnboardingManually()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text(LocalizedStringKey("settings.onboarding.showAgain"))
                        }
                    }
                    
                    Button {
                        showFaceNamingPromptManually()
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.rectangle.stack")
                                .foregroundStyle(.blue)
                            Text("Show Face Naming Prompt")
                                .foregroundStyle(.blue)
                        }
                    }
                } header: {
                    Text(LocalizedStringKey("settings.onboarding.header"))
                } footer: {
                    Text("Test the welcome face naming flow even with existing contacts")
                }
                
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
                
                Section {
                    Button(role: .destructive) {
                        resetAndShowOnboarding()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text(LocalizedStringKey("settings.onboarding.reset"))
                        }
                    }
                } footer: {
                    Text("Reset onboarding status and show the full flow immediately")
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
    
    private func showFaceNamingPromptManually() {
        print("🔵 [Settings] Show face naming prompt tapped")
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            print("🔵 [Settings] Showing face naming prompt after delay")
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                OnboardingCoordinatorManager.shared.showFaceNamingPrompt(
                    in: window,
                    modelContext: modelContext,
                    forced: true
                )
            }
        }
    }
    
    private func resetAndShowOnboarding() {
        print("🔵 [Settings] Reset onboarding tapped")
        
        OnboardingManager.shared.resetOnboarding()
        
        dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            print("🔵 [Settings] Showing onboarding after reset")
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first {
                OnboardingCoordinatorManager.shared.showOnboarding(
                    in: window,
                    forced: false,
                    modelContext: modelContext
                )
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
}