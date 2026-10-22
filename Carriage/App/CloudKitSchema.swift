#if DEBUG
import CoreData
import os
import SwiftData

/// Creates Carriage's record types in the iCloud container's Development environment, so they can be deployed to
/// Production in the CloudKit Dashboard. SwiftData only creates them lazily, so this pushes the whole model up once.
/// Debug builds only: launch with `-initCloudKitSchema` on a device signed in to iCloud.
enum CloudKitSchema {
    static func initializeIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") else { return }
        let log = Logger(subsystem: "Carriage", category: "CloudKitSchema")
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [Page.self, WritingDay.self, Notebook.self, PageVersion.self]) else {
            log.error("schema: couldn't build the model")
            return
        }
        // A throwaway store beside the real one, so the writer's pages are never touched.
        let url = URL.applicationSupportDirectory.appending(path: "CloudKitSchema.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.carriage.app")
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "CloudKitSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            log.error("schema: store failed to load: \(loadError.localizedDescription, privacy: .public)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            log.notice("schema: CloudKit schema initialized")
        } catch {
            log.error("schema: initialize failed: \(error.localizedDescription, privacy: .public)")
        }
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try? container.persistentStoreCoordinator.remove(store)
        }
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
}
#endif
