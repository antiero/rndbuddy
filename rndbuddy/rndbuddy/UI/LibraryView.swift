import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var favourites = false
    @State private var importing = false
    @State private var exporting = false
    @State private var file = LibraryFile()
    @State private var exportType = UTType.json
    @State private var error: String?
    @State private var editing: PatchDocument?
    @State private var deleting: PatchDocument?
    private var filtered: [PatchDocument] {
        (model.library?.patches ?? []).filter {
            (!favourites || $0.favourite) && (search.isEmpty || ($0.name + " " + $0.tags + " " + $0.snapshot.seedHex).localizedStandardContains(search))
        }
    }
    var body: some View {
        List {
            if !model.session.recent.isEmpty && search.isEmpty && !favourites {
                Section("Recent · on this device") {
                    ForEach(Array(model.session.recent.enumerated()), id: \.offset) { _, snapshot in
                        HStack {
                            VStack(alignment:.leading) { Text(snapshot.seedHex).monospaced(); Text(snapshot.recallDescription).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Save", systemImage: "bookmark") { editing = PatchDocument(name: "RND \(snapshot.seedHex)", snapshot: snapshot) }
                        }
                    }
                }
            }
            Section {
                ForEach(filtered) { patch in
                    HStack(spacing:14) {
                        Button { var copy=patch; copy.favourite.toggle(); model.library?.save(copy) } label: { Image(systemName:patch.favourite ? "star.fill" : "star").foregroundStyle(patch.favourite ? Design.accent : .secondary) }
                            .buttonStyle(.plain).accessibilityLabel(patch.favourite ? "Remove favourite" : "Favourite patch")
                        VStack(alignment:.leading,spacing:4) {
                            Text(patch.name).font(.headline)
                            Text(patch.tags.isEmpty ? patch.snapshot.seedHex : patch.tags).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load",systemImage:"play") { model.performance.cancel(); model.session.recall(patch.snapshot) }.disabled(!model.session.canEdit || model.session.recalling)
                    }.padding(.vertical,8)
                    .contextMenu {
                        Button("Edit Details",systemImage:"pencil") { editing=patch }
                        Button("Duplicate",systemImage:"plus.square.on.square") { var copy=patch; copy.name += " copy"; model.library?.save(copy,newIdentity:true) }
                        Button("Delete",systemImage:"trash",role:.destructive) { deleting=patch }
                    }
                }
            } header: { Text("Saved patches") }
        }
        .overlay { if filtered.isEmpty && model.session.recent.isEmpty { ContentUnavailableView("Your patch collection",systemImage:"square.stack",description:Text("Save a sound from RND, or import a patch library.")) } }
        .navigationTitle("Library").searchable(text:$search,prompt:"Names, tags or seeds")
        .toolbar {
            ToolbarItemGroup(placement:.automatic) {
                Toggle("Favourites",systemImage:"star",isOn:$favourites).toggleStyle(.button)
                Menu {
                    Button("Import Library…",systemImage:"square.and.arrow.down") { importing=true }
                    Button("Export Archive…") { export(csv:false) }
                    Button("Export JG CSV…") { export(csv:true) }
                } label: { Label("Library files",systemImage:"ellipsis.circle") }
            }
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json,.commaSeparatedText]) { result in
            do { try model.importLibraryFile(result.get()) } catch { self.error=error.localizedDescription }
        }
        .fileExporter(isPresented:$exporting,document:file,contentType:exportType,defaultFilename:"rndbuddy-library") { result in if case .failure(let failure)=result { error=failure.localizedDescription } }
        .sheet(item:$editing) { patch in PatchDetailsEditor(patch:patch) { model.library?.save($0) } }
        .alert("Library",isPresented:Binding(get:{ error != nil || model.library?.error != nil },set:{ if !$0 { error=nil; model.library?.error=nil } })) { Button("OK") { error=nil; model.library?.error=nil } } message: { Text(error ?? model.library?.error ?? "") }
        .confirmationDialog("Delete this patch?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting=nil } }),titleVisibility:.visible) {
            Button("Delete",role:.destructive) { if let deleting { model.library?.remove(deleting.id) }; deleting=nil }
        }
    }
    private func export(csv:Bool) {
        do {
            let patches=model.library?.patches ?? []
            file=LibraryFile(data:csv ? Data(PatchCSV.encode(patches).utf8) : try JSONEncoder().encode(PatchArchive(patches:patches,mappings:try model.library?.mappings.map { try $0.document() }, pages: model.performance.pages)))
            exportType=csv ? .commaSeparatedText : .json; exporting=true
        } catch { self.error=error.localizedDescription }
    }
}
struct SavePatchView: View {
    let model: AppModel
    var body: some View {
        PatchDetailsEditor(patch:PatchDocument(name:"RND \(model.session.snapshot.seedHex)",snapshot:model.session.snapshot)) { model.library?.save($0) }
    }
}
struct PatchDetailsEditor: View {
    @State var patch: PatchDocument
    let save: (PatchDocument)->Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name",text:$patch.name)
                TextField("Tags",text:$patch.tags)
                Toggle("Favourite",isOn:$patch.favourite)
                LabeledContent("Seed",value:patch.snapshot.seedHex)
                LabeledContent("Recall",value:patch.snapshot.recallDescription)
                LabeledContent("Firmware",value:patch.snapshot.firmware.title)
                if patch.snapshot.firmware == .official14 && patch.snapshot.tracks.contains(where:{ $0.engineOverride != nil }) {
                    Text("Official engine changes can take a patch off-seed. Reloading restores the saved controls, but may not reproduce its exact sound.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).navigationTitle("Save Patch")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save(patch); dismiss() }.disabled(patch.snapshot.seed == nil || patch.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            }
        }.frame(minWidth:320,idealWidth:440,minHeight:340)
    }
}
