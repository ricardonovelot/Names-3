import SwiftData

enum BatchModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            FaceBatch.self,
            FaceBatchFace.self
        ])

        // Prefer CloudKit for cross-device sync
        let cloudConfig = ModelConfiguration(
            "batches",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Fallback to a local persistent store so the app continues to work
            print("Batch CloudKit ModelContainer failed: \(error). Falling back to local batches store.")
            let localConfig = ModelConfiguration(
                "batches-local",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create local Batch ModelContainer: \(error)")
            }
        }
    }()
}