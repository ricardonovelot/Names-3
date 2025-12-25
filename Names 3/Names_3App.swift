//
//  Names_3App.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Contact.self,
            Note.self,
            Tag.self,
            // FaceBatch models intentionally NOT added here to keep the Contacts store stable
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
            TabView {
                ContentView()
                    .tabItem {
                        Label("People", systemImage: "person.3")
                    }

                NotesFeedView()
                    .tabItem {
                        Label("Notes", systemImage: "note.text")
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}