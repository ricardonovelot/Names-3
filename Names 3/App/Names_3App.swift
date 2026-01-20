//
//  Names_3App.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import UIKit
import os
import TipKit

enum AppTab: Hashable {
    case people
    case home
}

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var tabSelection: AppTab = .people
    @State private var hasCheckedOnboarding = false
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "SwiftData")

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Contact.self,
            Note.self,
            Tag.self,
            QuickNote.self,
        ])

        let cloudConfig = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
        )

        do {
            Names_3App.logger.info("Initializing SwiftData container with CloudKit")
            let container = try ModelContainer(for: schema, configurations: [cloudConfig])
            Self.ensureUniqueUUIDs(in: container)
            return container
        } catch {
            Names_3App.logger.error("CloudKit ModelContainer init failed: \(error, privacy: .public). Falling back to local store.")
            let localConfig = ModelConfiguration(
                "local-fallback",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfig])
                Self.ensureUniqueUUIDs(in: container)
                return container
            } catch {
                fatalError("Could not create local fallback ModelContainer: \(error)")
            }
        }
    }()

    // Synchronous uniqueness migration (preserves data) without generic/keyPath
    @MainActor
    private static func ensureUniqueUUIDs(in container: ModelContainer) {
        let context = ModelContext(container)
        let zeroUUIDString = "00000000-0000-0000-0000-000000000000"
        let defaultsKey = "Names3.didFixUUIDs.v1"
        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return
        }

        var anyFixed = false

        func fixContacts() {
            do {
                let all = try context.fetch(FetchDescriptor<Contact>())
                var seen = Set<UUID>()
                var fixed = 0
                for c in all {
                    var u = c.uuid
                    if u.uuidString == zeroUUIDString || seen.contains(u) {
                        var newU = UUID()
                        while seen.contains(newU) {
                            newU = UUID()
                        }
                        c.uuid = newU
                        u = newU
                        fixed += 1
                    }
                    seen.insert(u)
                }
                if fixed > 0 {
                    try context.save()
                    anyFixed = true
                    logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Contact")
                }
            } catch {
                logger.error("❌ Failed UUID fix for Contact: \(error, privacy: .public)")
            }
        }

        func fixNotes() {
            do {
                let all = try context.fetch(FetchDescriptor<Note>())
                var seen = Set<UUID>()
                var fixed = 0
                for n in all {
                    var u = n.uuid
                    if u.uuidString == zeroUUIDString || seen.contains(u) {
                        var newU = UUID()
                        while seen.contains(newU) {
                            newU = UUID()
                        }
                        n.uuid = newU
                        u = newU
                        fixed += 1
                    }
                    seen.insert(u)
                }
                if fixed > 0 {
                    try context.save()
                    anyFixed = true
                    logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Note")
                }
            } catch {
                logger.error("❌ Failed UUID fix for Note: \(error, privacy: .public)")
            }
        }

        func fixTags() {
            do {
                let all = try context.fetch(FetchDescriptor<Tag>())
                var seen = Set<UUID>()
                var fixed = 0
                for t in all {
                    var u = t.uuid
                    if u.uuidString == zeroUUIDString || seen.contains(u) {
                        var newU = UUID()
                        while seen.contains(newU) {
                            newU = UUID()
                        }
                        t.uuid = newU
                        u = newU
                        fixed += 1
                    }
                    seen.insert(u)
                }
                if fixed > 0 {
                    try context.save()
                    anyFixed = true
                    logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Tag")
                }
            } catch {
                logger.error("❌ Failed UUID fix for Tag: \(error, privacy: .public)")
            }
        }

        func fixQuickNotes() {
            do {
                let all = try context.fetch(FetchDescriptor<QuickNote>())
                var seen = Set<UUID>()
                var fixed = 0
                for q in all {
                    var u = q.uuid
                    if u.uuidString == zeroUUIDString || seen.contains(u) {
                        var newU = UUID()
                        while seen.contains(newU) {
                            newU = UUID()
                        }
                        q.uuid = newU
                        u = newU
                        fixed += 1
                    }
                    seen.insert(u)
                }
                if fixed > 0 {
                    try context.save()
                    anyFixed = true
                    logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in QuickNote")
                }
            } catch {
                logger.error("❌ Failed UUID fix for QuickNote: \(error, privacy: .public)")
            }
        }

        fixContacts()
        fixNotes()
        fixTags()
        fixQuickNotes()

        if anyFixed {
            UserDefaults.standard.set(true, forKey: defaultsKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TipManager.shared.configure()
                }
                .onAppear {
                    if !hasCheckedOnboarding {
                        hasCheckedOnboarding = true
                        checkAndShowOnboarding()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func checkAndShowOnboarding() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                print("❌ [App] No window found for onboarding")
                return
            }
            
            print("🔵 [App] Checking onboarding status")
            
            let modelContext = ModelContext(self.sharedModelContainer)
            OnboardingCoordinatorManager.shared.showOnboarding(
                in: window,
                forced: false,
                modelContext: modelContext
            )
        }
    }
}