import SwiftUI

struct MappingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My mapping"
    var body: some View {
        NavigationStack {
            Form {
                Section("Play") {
                    Picker("Vertical control", selection: Binding(get: { model.performance.playYAxis }, set: { model.performance.playYAxis = $0 })) {
                        ForEach(PlayYAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .help("Track volume changes continuously for all held notes. Velocity applies when a note starts.")
                    .accessibilityHint("Track volume affects all held notes on the selected track. Velocity applies only when a note starts.")
                }
                axis("Horizontal / roll", binding: Binding(get: { model.performance.mapping.x }, set: { model.performance.mapping.x = $0 }))
                axis("Vertical / pitch", binding: Binding(get: { model.performance.mapping.y }, set: { model.performance.mapping.y = $0 }))
                Section("Saved mappings") {
                    TextField("Name", text: $name)
                    Button("Save Mapping") { model.library?.saveMapping(name: name, mapping: model.performance.mapping) }.disabled(name.trimmingCharacters(in:.whitespaces).isEmpty)
                    ForEach(model.library?.mappings ?? [], id: \.recordID) { saved in
                        Button(saved.name) { if let mapping = try? JSONDecoder().decode(PerformanceMapping.self, from: saved.payload) { model.performance.mapping = mapping } }
                    }
                }
            }.formStyle(.grouped).navigationTitle("Assignments")
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.frame(minWidth:320,idealWidth:500,minHeight:450)
    }
    private func axis(_ name: String, binding: Binding<AxisMapping>) -> some View {
        Section(name) {
            Picker("Parameter", selection: binding.target) {
                ForEach(MappingTarget.allCases.filter { FirmwareCapabilities.supports($0, firmware: model.session.snapshot.firmware) }) { target in Text(target.rawValue).tag(target) }
            }
            Toggle("Invert", isOn: binding.inverted)
            Slider(value: binding.minimum, in: 0...1) { Text("Minimum") }
            Slider(value: binding.maximum, in: 0...1) { Text("Maximum") }
            Slider(value: binding.smoothing, in: 0...0.95) { Text("Smoothing") }
            Slider(value: binding.deadZone, in: 0...0.1) { Text("Dead zone") }
        }
    }
}
