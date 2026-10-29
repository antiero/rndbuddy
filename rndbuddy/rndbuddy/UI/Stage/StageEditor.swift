import SwiftUI
import UniformTypeIdentifiers

/// Selection and commands are shared by the canvas and its inspector.
@MainActor @Observable final class StageEditor {
    var selection: UUID?
    private var undoStack: [[PerformancePage]] = []
    private var redoStack: [[PerformancePage]] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func change(_ model: AppModel, _ edit: (inout [PerformancePage]) -> Void) {
        var pages = model.performance.pages
        edit(&pages)
        guard pages != model.performance.pages else { return }
        guard !pages.isEmpty, pages.count <= 1_000 else { model.stageError = "A library can contain 1 to 1,000 pages."; return }
        do {
            for page in pages { try page.validate() }
            undoStack.append(model.performance.pages); if undoStack.count > 50 { undoStack.removeFirst() }; redoStack.removeAll()
            model.performance.pages = pages
            model.performance.pageIndex = min(model.performance.pageIndex, max(0, pages.count - 1))
            model.savePages()
        } catch { model.stageError = error.localizedDescription }
    }
    func undo(_ model: AppModel) {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(model.performance.pages); model.performance.pages = previous
        model.performance.pageIndex = min(model.performance.pageIndex, previous.count - 1); model.savePages()
    }
    func redo(_ model: AppModel) {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(model.performance.pages); model.performance.pages = next
        model.performance.pageIndex = min(model.performance.pageIndex, next.count - 1); model.savePages()
    }
    func update(_ model: AppModel, control: ControlSpec) {
        change(model) { pages in
            let p = model.performance.pageIndex
            if let c = pages[p].controls.firstIndex(where: { $0.id == control.id }) { pages[p].controls[c] = control }
        }
    }
    func place(_ model: AppModel, _ requested: Placement) {
        var placement = requested
        let grid = model.stageLayout.grid
        let kind = model.performance.page.controls.first { $0.id == requested.controlID }?.kind ?? .trigger
        let minimum = PerformanceLayout.minimumSize(kind)
        placement.width = placement.width.clamped(minimum.width...grid.columns)
        placement.height = placement.height.clamped(minimum.height...grid.rows)
        placement.column = placement.column.clamped(0...(grid.columns - placement.width))
        placement.row = placement.row.clamped(0...(grid.rows - placement.height))
        change(model) { pages in
            let p = model.performance.pageIndex, layout = model.stageLayout
            var list = PerformanceLayout.flow(pages[p], in: layout).placements
            list.removeAll { $0.controlID == placement.controlID }; list.append(placement)
            pages[p].placements[layout] = list
        }
    }
    func add(_ kind: ControlKind, model: AppModel) {
        guard model.performance.page.controls.count < PerformancePage.maxControls else { return }
        let control = ControlSpec(kind: kind, title: kind.rawValue.capitalized,
            bindings: kind == .xy ? [ControlBinding(.volume), ControlBinding(.reverb)] : [.fader, .toggle].contains(kind) ? [ControlBinding(.masterVolume)] : [],
            action: kind == .trigger ? .hold : nil)
        change(model) { $0[model.performance.pageIndex].controls.append(control) }; selection = control.id
    }
}

struct StageEditorInspector: View {
    @Bindable var model: AppModel
    @Bindable var editor: StageEditor
    @State private var exporting = false
    @State private var importing = false
    @State private var file = LibraryFile()
    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("Name", text: pageName)
                    HStack {
                        Button("New", systemImage: "plus") {
                            editor.change(model) { $0.append(PerformancePage(name: "New page", controls: [])) }
                            model.performance.pageIndex = model.performance.pages.count - 1; editor.selection = nil
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            editor.change(model) { $0.append(model.performance.page.copied(name: model.performance.page.name + " copy")) }
                            model.performance.pageIndex = model.performance.pages.count - 1
                        }
                    }
                    HStack {
                        Button("Earlier", systemImage: "arrow.left") { movePage(-1) }.disabled(model.performance.pageIndex == 0)
                        Button("Later", systemImage: "arrow.right") { movePage(1) }.disabled(model.performance.pageIndex == model.performance.pages.count - 1)
                    }
                    Button("Delete Page", role: .destructive) {
                        editor.change(model) { $0.remove(at: model.performance.pageIndex) }; editor.selection = nil
                    }.disabled(model.performance.pages.count <= 1)
                }
                Section("Controls") {
                    Menu("Add Control", systemImage: "plus") {
                        ForEach(ControlKind.allCases, id: \.self) { kind in Button(kind.rawValue.capitalized) { editor.add(kind, model: model) } }
                    }.disabled(model.performance.page.controls.count >= PerformancePage.maxControls)
                    ForEach(model.performance.page.controls) { control in
                        Button { editor.selection = control.id } label: {
                            HStack { Text(control.title); Spacer(); if editor.selection == control.id { Image(systemName: "checkmark") } }
                        }
                    }
                }
                if let control = model.performance.page.controls.first(where: { $0.id == editor.selection }) {
                    ControlInspector(model: model, editor: editor, control: control)
                }
                Section {
                    HStack {
                        Button("Undo", systemImage: "arrow.uturn.backward") { editor.undo(model) }.disabled(!editor.canUndo).keyboardShortcut("z")
                        Button("Redo", systemImage: "arrow.uturn.forward") { editor.redo(model) }.disabled(!editor.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                    }
                    Button("Export Page", systemImage: "square.and.arrow.up") {
                        do { file = LibraryFile(data: try JSONEncoder().encode(PatchArchive(patches: [], pages: [model.performance.page]))); exporting = true }
                        catch { model.stageError = error.localizedDescription }
                    }
                    Button("Import Pages", systemImage: "square.and.arrow.down") { importing = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit layout")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.editingStage = false } } }
        }
        .fileExporter(isPresented: $exporting, document: file, contentType: .json, defaultFilename: model.performance.page.name) { result in
            if case .failure(let error) = result { model.stageError = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 32_000_000 else { throw PatchArchive.ArchiveError.invalid }
                let incoming = try PatchArchive.decode(data).pages ?? []
                guard model.performance.pages.count + incoming.count <= 1_000 else { throw PatchArchive.ArchiveError.invalid }
                editor.change(model) { $0.append(contentsOf: incoming.map { $0.copied() }) }
            } catch { model.stageError = error.localizedDescription }
        }
    }
    private var pageName: Binding<String> {
        Binding(get: { model.performance.page.name }, set: { value in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            editor.change(model) { $0[model.performance.pageIndex].name = String(value.prefix(80)) }
        })
    }
    private func movePage(_ delta: Int) {
        let old = model.performance.pageIndex, new = old + delta
        guard model.performance.pages.indices.contains(new) else { return }
        editor.change(model) { $0.swapAt(old, new) }; model.performance.pageIndex = new
    }
}
