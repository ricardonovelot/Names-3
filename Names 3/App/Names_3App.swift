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

enum AppTab: Hashable {
    case people
    case home
}

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var tabSelection: AppTab = .people
    
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
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            Names_3App.logger.error("CloudKit ModelContainer init failed: \(error, privacy: .public). Falling back to local store.")
            let localConfig = ModelConfiguration(
                "local-fallback",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create local fallback ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tabSelection) {
                ContentView()
                    .tabItem {
                        Label("People", systemImage: "person.3")
                    }
                    .tag(AppTab.people)
                
                HomeView(tabSelection: $tabSelection)
                    .tabItem {
                        Label("Recent", systemImage: "house")
                    }
                    .tag(AppTab.home)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}