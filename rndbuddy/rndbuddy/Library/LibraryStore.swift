import Foundation
import SwiftData
import Observation
import UniformTypeIdentifiers
import Security
import CoreData
import SwiftUI

enum LibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SavedPatch.self, SavedMapping.self] }
    @Model final class SavedPatch {
        var recordID: UUID = UUID()
        var revisionID: String = UUID().uuidString
        var tombstone: Bool = false
        var name: String = "Untitled"
        var tags: String = ""
        var favourite: Bool = false
        var modifiedAt: Date = Date()
        var payload: Data = Data()
        init(document: PatchDocument, tombstone: Bool = false) throws {
            self.tombstone = tombstone; revisionID = UUID().uuidString
            recordID = document.id; name = document.name; tags = document.tags
            favourite = document.favourite; modifiedAt = document.modifiedAt
            payload = try JSONEncoder().encode(document.snapshot)
        }
        func document() throws -> PatchDocument {
            PatchDocument(id: recordID, name: name, tags: tags, favourite: favourite, modifiedAt: modifiedAt, snapshot: try JSONDecoder().decode(PatchSnapshot.self, from: payload))
        }
    }
    @Model final class SavedMapping {
        var recordID: UUID = UUID()
        var name: String = "My mapping"
        var modifiedAt: Date = Date()
        var payload: Data = Data()
        init(name: String, mapping: PerformanceMapping) throws { self.name = name; recordID=UUID(); payload = try JSONEncoder().encode(mapping) }
        func document() throws -> MappingDocument {
            MappingDocument(id:recordID,name:name,modifiedAt:modifiedAt,mapping:try JSONDecoder().decode(PerformanceMapping.self,from:payload))
        }
    }
}
enum LibraryMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
typealias SavedPatch = LibrarySchemaV1.SavedPatch
typealias SavedMapping = LibrarySchemaV1.SavedMapping

@MainActor @Observable final class LibraryStore {
    let container: ModelContainer
    private(set) var patches: [PatchDocument] = []
    private(set) var mappings: [SavedMapping] = []
    private(set) var syncStatus: String
    var error: String?
    private var observers:[NSObjectProtocol]=[]

    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        if inMemory {
            container = try ModelContainer(for: schema, migrationPlan: LibraryMigration.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            syncStatus = "Preview"
        } else if !Self.hasCloudEntitlement {
            let configuration = ModelConfiguration("Library", schema: schema, cloudKitDatabase: .none)
            container = try ModelContainer(for: schema, migrationPlan: LibraryMigration.self, configurations: configuration)
            syncStatus = "Local library · iCloud requires a provisioned build"
        } else {
            do {
                let configuration = ModelConfiguration("Library", schema: schema, cloudKitDatabase: .private("iCloud.com.5of12.rndbuddy"))
                container = try ModelContainer(for: schema, migrationPlan: LibraryMigration.self, configurations: configuration)
                syncStatus = "iCloud configured · sync depends on your account"
            } catch {
                // Same local store name, preserving local records if iCloud is unavailable.
                let configuration = ModelConfiguration("Library", schema: schema, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, migrationPlan: LibraryMigration.self, configurations: configuration)
                syncStatus = "Local library · iCloud unavailable"
            }
        }
        reload()
        for name in [Notification.Name.NSPersistentStoreRemoteChange,NSPersistentCloudKitContainer.eventChangedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            })
        }
    }
    private static var hasCloudEntitlement: Bool {
        #if targetEnvironment(simulator)
        false
        #elseif os(macOS)
        if let task = SecTaskCreateFromSelf(nil),
           let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] {
            return containers.contains("iCloud.com.5of12.rndbuddy")
        }
        return false
        #else
        #if DEBUG
        return Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        #else
        return true // Distribution signing must include the configured CloudKit capability.
        #endif
        #endif
    }
    func reload() {
        do {
            let context = ModelContext(container)
            let records = try context.fetch(FetchDescriptor<SavedPatch>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse),SortDescriptor(\.revisionID,order:.reverse)]))
            // Immutable revisions keep payload and metadata together across CloudKit's
            // field-level merges. Newest revision wins; tombstones prevent resurrection.
            var seen: Set<UUID> = []
            patches = try records.filter { seen.insert($0.recordID).inserted }.filter { !$0.tombstone }.map { try $0.document() }
            mappings = try context.fetch(FetchDescriptor<SavedMapping>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]))
        } catch { self.error = error.localizedDescription }
    }
    private func nextRevisionDate(for id: UUID) -> Date {
        // Older SwiftData runtimes can round persisted timestamps. Keep local
        // revisions at least a millisecond apart before applying the tie-breaker.
        let latest = (try? container.mainContext.fetch(FetchDescriptor<SavedPatch>()))?.filter { $0.recordID == id }.map(\.modifiedAt).max()
        return max(.now,latest?.addingTimeInterval(0.001) ?? .distantPast)
    }
    func save(_ document: PatchDocument, newIdentity: Bool = false) {
        do {
            var value = document
            if newIdentity { value.id = UUID() }
            value.modifiedAt = nextRevisionDate(for:value.id)
            container.mainContext.insert(try SavedPatch(document:value))
            try container.mainContext.save(); reload()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ id: UUID) {
        do {
            guard let document = patches.first(where:{ $0.id == id }) else { return }
            var deletion = document; deletion.modifiedAt = nextRevisionDate(for:id)
            let tombstone = try SavedPatch(document:deletion,tombstone:true)
            container.mainContext.insert(tombstone)
            try container.mainContext.save(); reload()
        } catch { self.error = error.localizedDescription }
    }
    func saveMapping(name: String, mapping: PerformanceMapping) {
        do { container.mainContext.insert(try SavedMapping(name: name, mapping: mapping)); try container.mainContext.save(); reload() }
        catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 32_000_000 else { throw PatchArchive.ArchiveError.invalid }
        let incoming: [PatchDocument]
        let incomingMappings:[MappingDocument]
        if url.pathExtension.lowercased() == "csv" {
            guard let text = String(data: data, encoding: .utf8) else { throw PatchArchive.ArchiveError.invalid }
            incoming = try PatchCSV.decode(text); incomingMappings=[]
        } else { let archive=try PatchArchive.decode(data); incoming=archive.patches; incomingMappings=archive.mappings ?? [] }
        // Validate all records before making any persistent changes.
        let records = try incoming.map { patch -> SavedPatch in
            var copy = patch; copy.id = UUID(); copy.modifiedAt = .now
            return try SavedPatch(document: copy)
        }
        let mappingRecords=try incomingMappings.map { try SavedMapping(name:$0.name,mapping:$0.mapping) }
        for record in records { container.mainContext.insert(record) }
        for record in mappingRecords { container.mainContext.insert(record) }
        try container.mainContext.save(); reload()
    }
}
struct LibraryFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
