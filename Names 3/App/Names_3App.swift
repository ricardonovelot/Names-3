//
//  Names_3App.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import UIKit

enum AppTab: Hashable {
    case people
    case home
}

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var tabSelection: AppTab = .people
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Contact.self,
            Note.self,
            Tag.self,
            QuickNote.self,
        ])
        let modelConfiguration = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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