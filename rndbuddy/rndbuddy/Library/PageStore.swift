import Foundation
import SwiftData

/// Deliberately separate from the CloudKit patch store.
enum PageSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [PageRecord.self, MigrationRecord.self] }
    @Model final class PageRecord {
        var id: UUID = UUID()
        var order: Int = 0
        var payload: Data = Data()
        init(page: PerformancePage, order: Int) throws {
            id = page.id; self.order = order; payload = try JSONEncoder().encode(page)
        }
    }
    @Model final class MigrationRecord {
        var key: String = ""
        init(_ key: String) { self.key = key }
    }
}
enum PageMigration: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PageSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
@MainActor final class PageStore {
    let container: ModelContainer
    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: PageSchemaV1.self)
        let config = ModelConfiguration("StagePages", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, migrationPlan: PageMigration.self, configurations: config)
    }
    func load(mappings: [MappingDocument]) throws -> [PerformancePage] {
        let context = container.mainContext
        var markers = Set(try context.fetch(FetchDescriptor<PageSchemaV1.MigrationRecord>()).map(\.key))
        var pages = try context.fetch(FetchDescriptor<PageSchemaV1.PageRecord>(sortBy: [SortDescriptor(\.order)]))
            .map { try JSONDecoder().decode(PerformancePage.self, from: $0.payload) }
        if !markers.contains("defaults") {
            pages.append(contentsOf: PerformancePage.defaults)
            context.insert(PageSchemaV1.MigrationRecord("defaults")); markers.insert("defaults")
        }
        for mapping in mappings where !markers.contains(mapping.id.uuidString) {
            pages.append(PerformancePage(legacy: mapping.mapping, name: mapping.name))
            context.insert(PageSchemaV1.MigrationRecord(mapping.id.uuidString))
        }
        try replace(pages)
        return pages
    }
    func replace(_ pages: [PerformancePage]) throws {
        guard pages.count <= 1_000 else { throw PatchArchive.ArchiveError.invalid }
        for page in pages { try page.validate() }
        let context = container.mainContext
        do {
            let records = try pages.enumerated().map { try PageSchemaV1.PageRecord(page: $0.element, order: $0.offset) }
            for record in try context.fetch(FetchDescriptor<PageSchemaV1.PageRecord>()) { context.delete(record) }
            for record in records { context.insert(record) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}

extension PerformancePage {
    func copied(name: String? = nil) -> PerformancePage {
        let ids = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, UUID()) })
        let copies = controls.map { control in
            ControlSpec(id: ids[control.id]!, kind: control.kind, title: control.title, bindings: control.bindings,
                        action: control.action, playYAxis: control.playYAxis)
        }
        var page = PerformancePage(name: name ?? self.name, controls: copies)
        page.placements = placements.mapValues { list in list.compactMap { placement in
            guard let id = ids[placement.controlID] else { return nil }
            var copy = placement; copy.controlID = id; return copy
        } }
        return page
    }
}
