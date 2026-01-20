import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
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
                } header: {
                    Text(LocalizedStringKey("settings.onboarding.header"))
                } footer: {
                    Text(LocalizedStringKey("settings.onboarding.footer"))
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
                        OnboardingManager.shared.resetOnboarding()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text(LocalizedStringKey("settings.onboarding.reset"))
                        }
                    }
                } footer: {
                    Text(LocalizedStringKey("settings.onboarding.resetFooter"))
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
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                print("❌ [Settings] No window found")
                return
            }
            
            print("✅ [Settings] Found window, calling coordinator manager")
            OnboardingCoordinatorManager.shared.showOnboarding(in: window, forced: true)
        }
    }
}

#Preview {
    SettingsView()
}