//
//  File.swift
//  Names 3
//
//  Created by Ricardo on 15/10/24.
//

import SwiftData

extension ModelContainer {
    static var sample: () throws -> ModelContainer = {
        let schema = Schema([AnimalCategory.self, Animal.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Task { @MainActor in
            AnimalCategory.insertSampleData(modelContext: container.mainContext)
        }
        return container
    }
}
